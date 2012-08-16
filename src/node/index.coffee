jar = require('jar')
querystring = require('querystring')
url = require('url')

multipart = require('./lib/multipart')

soma = require('..')

escapeXML = (s) ->
    return s.toString().replace /&(?!\w+;)|["<>]/g, (s) ->
        switch s 
            when '&' then return '&amp;'
            when '"' then return '&#34;'
            when '<' then return '&lt;'
            when '>' then return '&gt;'
            else return s
            
combineChunks = (chunks) ->
    size = 0
    for chunk in chunks
        size += chunk.length

    # Create the buffer for the file data
    result = new Buffer(size)

    size = 0
    for chunk in chunks
        chunk.copy(result, size, 0)
        size += chunk.length

    return result


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

        callback(el) if callback
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
        
    setManifest: (src) ->
        @context.addManifest(src)
        
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
            # attributes['defer'] = 'defer'
            attributes['data-loading'] = 'loading'
            attributes['onload'] = "this.removeAttribute('data-loading');"
                        
        return @loadElement 'script', attributes, text, callback
        
    loadStylesheet: (attributes, callback) ->
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

        return @loadElement 'link', attributes, text, callback

    loadTemplate: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        # Templates must be inlined, otherwise they won't load
        text = soma.files[attributes.src]
        attributes['data-src'] = attributes.src
        delete attributes.src
            
        attributes.type = 'text/plain'
        attributes.charset = 'utf8'

        @loadElement 'script', attributes, text, callback
        return text

    loadImage: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }
            
        attributes['data-loading'] = 'loading'
        attributes['onload'] = "this.removeAttribute('data-loading');"

        return @loadElement 'img', attributes, callback

    loadData: (options, callback) ->
        result = {}
        _success = options.success
        _error = options.error
    
        done = @wait(callback)
        options.success = (data) =>
            for key in data
                result[key] = data[key]

            _success(data) if _success
            done()
        
        options.error = (status, response) =>
            if _error
                _error(status, response, options)
            else
                @emit('error', 'loadData', status, response, options)

            done()
    
        context = new soma.InternalContext(@context, options)
        context.begin()
        return
    

class soma.ClientContext extends soma.Context
    inlineScripts: false
    inlineStylesheets: false
    
    constructor: (@request, @response, scripts) ->
        urlParsed = url.parse(@request.url, true)
        for key of urlParsed
            @[key] = urlParsed[key]

        @cookies = new jar.Jar(@request, @response, ['$ecret']) # FIX THIS!
        @head = {}
        
        @addHeadElement(new Element('title'))
        @addHeadElement(new Element('meta', { charset: 'utf-8' }))
        
        for script in scripts
            attributes =
                src: script
                type: 'text/javascript'
                charset: 'utf8'
                # defer: 'defer'
                onload: "this.removeAttribute('data-loading');"
                'data-loading': 'loading'
                
            @addHeadElement(new Element('script', attributes))
        
    addHeadElement: (el) ->
        if el.headerKey()
            @head[el.headerKey()] = el
            
        return
        
    addManifest: (src) ->
        @manifest = "manifest=#{src}"
    
    begin: ->
        contentType = @request.headers['content-type']
        contentType = contentType.split(/;/)[0] if contentType
        switch contentType
            when undefined then @route({})
            when 'application/x-www-form-urlencoded' then @_readUrlEncoded()
            when 'application/json' then @_readJSON()
            when 'application/octet-stream' then @_readBinary()
            when 'multipart/form-data' then @_readFormData()
        
        return
        
    route: (@data) ->
        results = soma.router.run(@path, @)
        
        if not results.length
            @send(404)

        else
            for result in results
                if result instanceof soma.Chunk
                    @send(result)
        
        return
        
    send: (statusCode, body, contentType) ->
        if typeof statusCode isnt 'number'
            contentType = body
            body = statusCode
            statusCode = 200
        
        body or= ''
        
        if body instanceof soma.Chunk
            if @chunk
                throw new Error('Cannot send multiple chunks')

            @chunk = body

            while @chunk.meta
                @chunk = @chunk.meta()
            
            @chunk.on 'complete', =>
                @chunk.emit('render')
                
                @send """
                    <!doctype html>
                    <html #{@manifest or ''}>
                    <head>
                        #{(value for key, value of @head).join('\n    ')}
                    </head>
                    <body>
                        #{@chunk.html}
                    </body>
                    </html>
                """
            
            @chunk.load(this)
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

        if not @cookies.get('_csrf_token', {raw: true})
            @cookies.set('_csrf_token', Math.random().toString().substr(2), {raw: true})

        @response.statusCode = statusCode
        @response.setHeader('Content-Type', contentType)
        @response.setHeader('Content-Length', contentLength)
        @cookies.setHeaders()
        @response.end(body)
        return
        
    sendError: (err, body) ->
        console.log(err.stack) if err
        @send(500, body)

    go: (path) ->
        if @chunk
            @chunk.emit('halt')
            @chunk = null
            
        @response.statusCode = 303
        @response.setHeader('Location', path)
        @cookies.setHeaders()
        @response.end()
        return false

    _readJSON: ->
        chunks = []
        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', () =>
            if @request.headers['x-csrf-token'] == @cookies.get('_csrf_token', {raw: true})
                @route(JSON.parse(chunks.join('')))
            else
                @sendError(null, 'Bad/missing CSRF token.')

        return
    
    _readBinary: ->
        chunks = []
        data = {}

        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', =>
            if @request.headers['x-csrf-token'] == @cookies.get('_csrf_token', {raw: true})
                data[@request.headers['x-file-name']] = combineChunks(chunks)
                @route(data)
            else
                @sendError(null, 'Bad/missing CSRF token.')
            
    _readUrlEncoded: ->
        chunks = []
        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', () =>
            data = querystring.parse(chunks.join(''))
            if data._csrf_token == @cookies.get('_csrf_token', {raw: true})
                delete data._csrf_token
                @route(data)
            else
                @sendError(null, 'Bad/missing CSRF token.')

        return
        
    _readFormData: ->
        chunks = []
        data = {}

        formData = new multipart.formData(@request)
        
        formData.on 'stream', (stream) =>
            chunks = []
            stream.on 'data', (chunk) => chunks.push(chunk)
            stream.on 'end', () => data[stream.name] = combineChunks(chunks)
        
        formData.on 'end', () =>
            if data._csrf_token == @cookies.get('_csrf_token', {raw: true})
                delete data._csrf_token
                @route(data)
            else
                @sendError(null, 'Bad/missing CSRF token.')

        formData.begin()
        return


class soma.InternalContext extends soma.Context
    constructor: (@parent, @options) ->
        @cookies = @parent.cookies
    
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

