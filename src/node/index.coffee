jar = require('jar')
querystring = require('querystring')
url = require('url')

upload = require('./lib/upload')

soma = require('..')

escapeXML = (s) ->
    return s.toString().replace /&(?!\w+;)|["<>]/g, (s) ->
        switch s 
            when '&' then return '&amp;'
            when '"' then return '&#34;'
            when '<' then return '&lt;'
            when '>' then return '&gt;'
            else return s
            

class Element
    isVoid: ->
        return @tag of {
            area: true, base: true, br: true, col: true, hr: true,
            img: true, input: true, link: true, meta: true,
            param: true, command: true, keygen: true, source: true,
        }
        
    constructor: (@tag, @attributes={}, @text='') ->
    
    headerKey: ->
        switch @tag
            when 'meta'
                if 'charset' of @attributes then 'meta-charset'
                else if 'name' of @attributes then "meta-name-#{@attributes.name}"
                else if 'http-equiv' of @attributes then "meta-http-#{@attributes['http-equiv']}"
                
            when 'title' then 'title'
            when 'link' then "link-#{@attributes.rel}-#{@attributes.href}"
            when 'script' then "script-#{@attributes.src}"
            when 'style' then "style-#{@attributes['data-href']}"
    
    toString: ->
        html = "<#{@tag}"
        for name, value of @attributes
            html += " #{name}=\"#{escapeXML(value)}\""
        
        html += if not @text and @isVoid() then ' />' else ">#{@text}</#{@tag}>"
        return html


class soma.Chunk extends soma.Chunk
    load: ->
        super
        @loadScript(@_src) if @_src
            
    loadElement: (tag, attributes, text, callback) ->
        el = new Element(tag, attributes, text)
        @context.addHeadElement(el)

        callback() if callback
        return el
    
    setTitle: (title) ->
        return @loadElement 'title', {}, title
    
    setMetaHeader: (attributes, content) ->
        if typeof attributes is 'string'
            attributes = { 'http-equiv': attributes, content: content }

        return @loadElement 'meta', attributes
        
    setMeta: (attributes, content) ->
        if typeof attributes is 'string'
            attributes = { name: attributes, content: content }

        return @loadElement 'meta', attributes
        
    loadScript: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.type = 'text/javascript'
        attributes.charset = 'utf8'

        if @context.inlineScripts
            text = soma.files[attributes.src]
            attributes['data-src'] = attributes.src
            delete attributes.src
            
        else
            attributes['defer'] = 'defer'
            attributes['data-loading'] = 'loading'
            attributes['onload'] = "this.removeAttribute('data-loading');"
                        
        return @loadElement 'script', attributes, text, callback
        
    loadStylesheet: (attributes) ->
        if typeof attributes is 'string'
            attributes = { href: attributes }

        if @context.inlineStylesheets
            tag = 'style'
            text = soma.files[attributes.href]
            attributes['data-href'] = attributes.href
            delete attributes.href
        else
            attributes.rel = 'stylesheet'

        attributes.type = 'text/css'
        attributes.charset = 'utf8'

        return @loadElement 'link', attributes, text

    loadTemplate: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        # Templates must be inlined, otherwise they won't load
        text = soma.files[attributes.src]
        attributes['data-src'] = attributes.src
        delete attributes.src
            
        attributes.type = 'text/plain'
        attributes.charset = 'utf8'

        @loadElement 'script', attributes, text
        return text

    loadImage: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }
            
        attributes['data-loading'] = 'loading'
        attributes['onload'] = "this.removeAttribute('data-loading');"

        return @loadElement 'img', attributes

    loadData: (options) ->
        result = {}
        _success = options.success
        _error = options.error
    
        done = @wait()
        options.success = (data) =>
            for key in data
                result[key] = data[key]

            _success(data) if _success
            done()
        
        options.error = (status, response) =>
            if _error
                _error(status, response, options)
            else
                @emit('error', 'requireData', status, response, options)

            done()
    
        context = new soma.InternalContext(@context, options)
        context.begin()

        return result
    

class soma.ClientContext extends soma.Context
    inlineScripts: false
    inlineStylesheets: false
    
    constructor: (@request, @response) ->
        urlParsed = url.parse(@request.url, true)
        for key of urlParsed
            @[key] = urlParsed[key]

        @jar = new jar.Jar(@request, @response, ['$ecret']) # FIX THIS!
        @head = {}
        
        defaultHead = [
            new Element('title')
            new Element('meta', { charset: 'utf-8' })
            new Element('script', { src: '/ender.js', type: 'text/javascript', charset: 'utf8' })
        ]
        
        for el in defaultHead
            @addHeadElement(el)
    
    addHeadElement: (el) ->
        if el.headerKey()
            @head[el.headerKey()] = el
            
        return
    
    begin: () ->
        switch @request.headers['content-type']
            when undefined, 'application/x-www-form-urlencoded' then @_readUrlEncoded()
            when 'application/json' then @_readJSON()
            when 'application/octet-stream', 'multipart/form-data' then @_readFiles()
        
        return
        
    route: (@data) ->
        results = soma.router.run(@path, @)
        if not results.length
            @send(404)

        else
            for result in results
                if result instanceof soma.Chunk
                    @send(chunk)
        
        return
        
    send: (statusCode, body, contentType) ->
        if typeof statusCode isnt 'number'
            contentType = body
            body = statusCode
            statusCode = 200
        
        body or= ''
        
        if body instanceof soma.Chunk
            chunk = result
            while chunk.meta
                chunk = chunk.meta()
                    
            chunk.on 'complete', =>
                chunk.emit('render')
                
                @send """
                    <!doctype html>
                    <html>
                    <head>
                        #{(value for key, value of @head).join('\n    ')}
                    </head>
                    <body>
                        #{chunk.html}
                    </body>
                    </html>
                """
            
            chunk.load(this)
            return

        if body instanceof Buffer
            contentType or= 'application/octet-stream'
            contentLength = body.length
    
        else
            if typeof body is 'object'
                body = JSON.stringify(body)
                contentType or= 'application/json'
            else
                contentType or= 'text/html'
                
            contentLength = Buffer.byteLength(body)

        @response.statusCode = statusCode
        @response.setHeader('Content-Type', contentType)
        @response.setHeader('Content-Length', contentLength)
        @response.end(body)
        return
        
    sendError: (err, body) ->
        console.log(err.stack) if err
        @send(500, body)

    go: (path) ->
        @response.statusCode = 303
        @response.setHeader('Location', path)
        @response.end()
        return

    _readJSON: () ->
        chunks = []
        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', () => @route(JSON.parse(chunks.join("")))
        return
    
    _readUrlEncoded: () ->
        chunks = []
        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', () => @route(querystring.parse(chunks.join("")))
        return
    
    _readFiles: () ->
        uploadRequest = new upload.UploadRequest(@request)

        uploadRequest.once 'file', (file) =>
            chunks = []
            file.on 'data', (chunk) => chunks.push(chunk)
            file.on 'end', () => @route(util.combineChunks(chunks))
        
        uploadRequest.begin()
        return


class soma.InternalContext extends soma.Context
    constructor: (@parent, @options) ->
        @jar = @parent.jar
    
    begin: -> soma.router.run(@options.url, @)

    send: (statusCode, body) ->
        if typeof statusCode isnt 'number'
            body = statusCode
            statusCode = 200
    
        if statusCode != 200
            return @options.error(statusCode, body)
    
        if typeof body isnt 'object'
            throw new Error('Internal contexts can only send JSON.')
    
        @options.success(body)

    sendError: (err, body) ->
        console.log(err.stack) if err
        @send(500, body)

    go: (path) -> @parent.go(path)
    

