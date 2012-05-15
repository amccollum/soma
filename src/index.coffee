soma = exports ? (@['soma'] = {})
events = require('events')

soma.Router = require('route').Router

soma.router = new soma.Router
soma.routes = (ob) -> soma.router.add(ob)

collect = (cls, fn, ob) ->
    if Array.isArray(ob)
        arr = ob
        ob = {}
        
        for item in arr
            ob[item.name] = item
            
    for name, item of ob
        if typeof item is 'object'
            # Convert object into subclass
            item = class extends cls
                for key, value of item
                    @::[key] = value
        
        item::_src = soma._src
        item.name or= name
        fn[name] = item
        
    return

soma.chunks = (ob) -> collect(soma.Chunk, soma.chunks, ob)
soma.views = (ob) -> collect(soma.View, soma.views, ob)

extend = (ob1, ob2) ->
    for key, value of ob2
        ob1[key] = value

decamelize = (s) -> s and s.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase()


class soma.EventMonitor extends events.EventEmitter
    events: []
    constructor: ->
        for event in @events
            @on event, @[event] if event of @


class soma.Widget extends soma.EventMonitor
    defaults: {}
    constructor: (options) ->
        @options = {}
        extend(@options, @defaults)
        extend(@options, options)
        super(@options)

        @status = null

    emit: (event) ->
        if event in @events
            @status = event
            
        super
        

# Placeholder class to inherit from
class soma.Context
    

# View is only used client-side
class soma.View extends soma.Widget
    events: ['create', 'complete', 'destroy']

    constructor: ->
        super
        
        # Convenience methods
        @context = @options.context
        @cookies = @context.cookies
        @go = => @context.go.apply(@context, arguments)

        @name = decamelize(@constructor.name)

        @el = $(@options.el)
        @el.data(@name, this)
        @el.one 'remove', (event) =>
            if event.target is @el[0]
                @el.data(@name, null)
                @emit('destroy')
        
        @emit('create')

    $: (selector) -> $(selector, @el)


class soma.Chunk extends soma.Widget
    events: ['prepare', 'loading', 'ready', 'error', 'build', 'complete', 'render', 'halt']

    constructor: ->
        super

        @errors = []
        @waiting = 0

    emit: (event) ->
        if @status isnt 'halt'
            super
            
        if event is 'halt'
            # For garbage collection purposes
            for event in @events
                @removeAllListeners(event)

    load: (@context) ->
        # Convenience methods
        @cookies = @context.cookies
        @go = => @context.go.apply(@context, arguments)

        if not @status
            # Give time to bind event handlers
            setTimeout(@wait(), 1)
            @emit('prepare', @options)

    toString: -> @html

    error: ->
        args = Array.prototype.slice.call(arguments)
        @errors.push(args)

    ready: ->
        if not @html
            @emit('build', @errors)
            @emit('complete')

    wait: (fn) ->
        if not @waiting++
            @emit('loading')

        return =>
            fn.apply(this, arguments) if fn
            if not --@waiting and @status != 'abort'
                @emit('ready')

    loadChunk: (chunk, options) ->
        if typeof chunk is 'function'
            chunk = new chunk(options)
    
        else if typeof chunk is 'string'
            chunk = new soma.chunks[chunk](options)
    
        if not chunk.html
            chunk.on 'complete', @wait()
            chunk.load(@context)
            
        return chunk


# Load node-specific code on the server
if process?.pid
    require('./node')
