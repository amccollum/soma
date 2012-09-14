soma = exports ? (@['soma'] = {})
events = require('events')

soma.Router = require('route').Router

soma.router = new soma.Router
soma.routes = (layout, routes) ->
    if typeof layout isnt 'string'
        routes = layout
        layout = null
        
    for expr, fn of routes
        soma.router.add expr, (@params) ->
            if @params
                for key, value of @params
                    @data[key] = value
                    
            if typeof fn is 'function'
                fn.call(@, @params)
                
            else
                chunk = fn
                if layout
                    @loadChunk layout, {chunk: chunk}, (html) ->
                        @build(html)

                else
                    @loadChunk chunk, (html) ->
                        @build(html)

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
        item::name = name
        fn[name] = item
        
    return

extend = (ob1, ob2) ->
    for key, value of ob2
        ob1[key] = value

decamelize = (s) -> s and s.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase()


_function_cache = {}

# Placeholder class to inherit from
class soma.Context
    constructor: () ->
        @modules = {}
        @globals = {}
        @url = '/'
    
    _dd =
        '/./': /// /\./ ///g
        '/.$': /// /\.$ ///
        '^/../': /// ^ /\.\./ ///
        '/../': /// (/([^/]*))? /\.\./ ///
        '/..$': /// (/([^/]*))? /\.\.$ ///

    resolve: (url) ->
        if /^https?:/.test(url)
            return url
            
        else if url.charAt('/') != '/'
            url = @url.replace(/\/[^\/]*$/, '') + url
            
        # Non-trailing single dots
        url = url.replace(@_dd['/./'], '/')
        
        # Trailing single dots
        url = url.replace(@_dd['/.$'], '/')
        
        # Non-trailing double dots
        while @_dd['/../'].test(url)
            url = url.replace(@_dd['/../'], '/')
        
        # Trailing double dots
        url = url.replace(@_dd['/..$'], '/')
        
        return url
    
    loadCode: (url, args=[], callback) ->
        url = @resolve(url)
        
        if typeof args is 'function'
            callback = args
            args = []
        
        key = [url].concat(args).join(',')
        
        if key of _function_cache
            callback(null, _function_cache[key])
        else
            @loadFile url, (err, js) ->
                callback.apply(@, arguments) if err
                callback(null, (_function_cache[key] = Function.apply(null, args.concat([js]))))
                return
                
        return

    loadChunk: (url, data, callback) ->
        url = @resolve(url)
        
        if typeof data is 'function'
            callback = data
            data = undefined
        
        subcontext = @createSubcontext
            build: (html) -> callback(null, html)
            url: url
    
        @loadCode url, ['soma', 'data'], (err, fn) ->
            callback.apply(this, arguments) if err            
            fn.apply(subcontext, soma, data)
            return
        
        return
        
    loadModule: (url, force, callback) ->
        url = @resolve(url)
        
        if typeof force is 'function'
            callback = force
            force = undefined
        
        if url of @modules
            callback(null, @modules[url].exports)
        
        @loadCode url, ['module', 'exports', 'soma'], (err, fn) =>
            callback.apply(this, arguments) if err

            @modules[url] = module = { exports: {} }
            fn.apply(@globals, module, module.exports, soma)
            
            callback(null, module.exports)
    
    createSubcontext: (attributes) ->
        parent = @
        return new class
            @:: = parent
            @::constructor = @
            
            constructor: ->
                for name, value of attributes
                    @[name] = value
                    
                return


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


# View is only used client-side
class soma.View extends soma.Widget
    events: ['create', 'complete', 'destroy']

    constructor: ->
        super
        
        # Convenience methods
        @context = @options.context
        @cookies = @context.cookies
        @go = => @context.go.apply(@context, arguments)

        dataName = decamelize(@name)

        @el = $(@options.el)
        @el.data(dataName, this)
        @el.one 'remove', (event) =>
            if event.target is @el[0]
                @el.data(dataName, null)
                @emit('destroy')
        
        @emit('create')

    $: (selector) -> $(selector, @el)


# Load node-specific code on the server
if process?.pid
    require('./node')
