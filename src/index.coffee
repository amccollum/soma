soma = exports ? (@['soma'] = {})
events = require('events')

soma.config = {}

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


_function_cache = {}

# Placeholder class to inherit from
class soma.Context extends events.EventEmitter
    constructor: () ->
        @modules = {}
        @globals = {}
        @views = []
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
        
    loadView: (url, callback) ->
        @views.append(url)
        @loadScript
            src: url
            type: 'text/plain'
            callback
        
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


# Load node-specific code on the server
if process?.pid
    require('./node')
