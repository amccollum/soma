soma = exports ? (@['soma'] = {})
events = require('events')

soma.bundled = {}
soma.config = {}

soma.Router = require('route').Router

soma.router = new soma.Router
soma.routes = (routes) ->
    for expr, fn of routes
        if typeof fn is 'function'
            soma.router.add expr, fn

        else if expr == 'layout'
            layout = fn

        else 
            do (chunk=fn) ->
                soma.router.add expr, (@params) ->
                    if layout
                        @loadChunk layout, {chunk: chunk}, (err, html) =>
                            throw err if err
                            @build(html)

                    else
                        @loadChunk chunk, (err, html) =>
                            throw err if err
                            @build(html)
                            
    return


_function_cache = {}

# Placeholder class to inherit from
class soma.Context extends events.EventEmitter
    constructor: () ->
        @modules = {}
        @globals = {}
        @views = []
        @url = '/'
    
    resolve: (url) ->
        if url.charAt(0) == '/' or /^https?:/.test(url)
            return url
        
        if ~(i = @url.lastIndexOf('/'))
            url = @url.substr(0, i+1) + url

        parts = url.substr(1).split('/')
        while ~(i = parts.indexOf('.'))
            parts.splice(i, 1)

        while ~(i = parts.indexOf('..'))
            if i then parts.splice(i-1, 2)
            else parts.shift()
        
        return '/' + parts.join('/')
    
    loadCode: (url, params=[], callback) ->
        url = @resolve(url)
        
        if typeof params is 'function'
            callback = params
            args = []
        
        key = [url].concat(params).join(':')
        
        if key of _function_cache
            callback(null, _function_cache[key])
        else
            @loadFile url, (err, js) ->
                return callback(arguments...) if err
                
                # Add source URL for better debugging
                js += "\n//@ sourceURL=#{url}"
                
                callback(null, (_function_cache[key] = Function.apply(null, params.concat([js]))))
                return
                
        return

    loadChunk: (url, data, callback) ->
        url = @resolve(url)
        
        if typeof data is 'function'
            callback = data
            data = {}
        
        subcontext = @createSubcontext
            url: url
            data: data
    
        @loadCode url, ['require', 'callback'], (err, fn) ->
            return callback(arguments...) if err
            fn.call(subcontext, require, callback)
            return
        
        return
        
    loadView: (url, callback) ->
        @views.push(url)
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
        
        @loadCode url, ['require', 'module', 'exports'], (err, fn) =>
            return callback(arguments...) if err

            @modules[url] = module = { exports: {} }
            fn.call(@globals, require, module, module.exports)
            
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
