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
                    
        item.name or= name
        fn[name] = item
        
    return

soma.pages = (ob) -> collect(soma.Page, soma.pages, ob)
soma.chunks = (ob) -> collect(soma.Chunk, soma.chunks, ob)
soma.views = (ob) -> collect(soma.View, soma.views, ob)

extend = (ob1, ob2) ->
    for key, value of ob2
        ob1[key] = value

decamelize = (s) -> s and s.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase()


# Placeholder classes to inherit from
class soma.Page
class soma.Context


class soma.EventMonitor extends events.EventEmitter
    events: []
    constructor: (options) ->
        for event in @events
            @on event, @[event] if event of @
            @on event, options[event] if event of options


class soma.Widget extends soma.EventMonitor
    defaults: {}
    constructor: (options) ->
        @options = {}
        extend(@options, @defaults)
        extend(@options, options)
        super(@options)

        @status = null

    emit: (event) ->
        @status = event
        super
        

class soma.View extends soma.Widget
    events: ['create', 'destroy']

    constructor: ->
        super

        @name = decamelize(@constructor.name)

        @el = soma.$(@options.el)
        @el.data(@name, this)
        @el.one 'remove', (event) =>
            if event.target is @el[0]
                @el.data(@name, null)
                @emit('destroy')
        
        @emit('create')

    $: (selector) -> soma.$(selector, @el)


class soma.Chunk extends soma.Widget
    events: ['prepare', 'loading', 'ready', 'error', 'build', 'complete']

    constructor: ->
        super

        @data = @options.data or {}
        @errors = []
        @waiting = 0

        if @options.html
            @html = @options.html
            @emit('complete')

    load: (@context) ->
        if not @status
            # Give time to bind event handlers
            setTimeout(@wait(), 1)
            @emit('prepare', @data)

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
            if not --@waiting
                @emit('ready')

    loadChunk: (chunk, options) ->
        if typeof chunk is 'function'
            chunk = new chunk(options)
    
        else if typeof chunk is 'string'
            chunk = new soma.chunks[chunk](options)
    
        chunk.on 'complete', @wait()
        chunk.load(@context)
        return chunk


# Load node-specific code on the server
if process?.pid
    require('./node')
