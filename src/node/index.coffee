crypto = require('crypto')
jar = require('jar')
querystring = require('querystring')
url = require('url')

multipart = require('./lib/multipart')

soma = require('..')

soma.config.engine = 'node'

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
            when 'script'
                if @attributes.src then "script-#{@attributes.src}"
                else "script-#{@text}"
                
            when 'style' then "style-#{@attributes['data-href']}"
    
    html: -> @text
    
    outerHTML: ->
        html = "<#{@tag}"
        for name, value of @attributes
            html += " #{name}=\"#{escapeXML(value)}\""
        
        html += if not @text and @isVoid() then ' />' else ">#{@text}</#{@tag}>"
        return html

    toString: @::outerHTML


class soma.Context extends soma.Context
    constructor: (@request, @response, scripts) ->
        super

        urlParsed = url.parse(@request.url, true)
        for key of urlParsed
            @[key] = urlParsed[key]

        @cookies = new jar.Jar(@request, @response, ['$ecret']) # FIX THIS!
        @head = {}
        
        @addHeadElement(new Element('title'))
        @addHeadElement(new Element('meta', { charset: 'utf-8' }))
        
        for script in scripts
            # This is an async call, but it's synchronous on the server
            @loadScript(script)
        
    addHeadElement: (el) ->
        if el.headerKey()
            @head[el.headerKey()] = el
            
        return
        
    addManifest: (src) ->
        @manifest = "manifest=#{src}"
    
    begin: ->
        contentType = @request.headers['content-type']
        contentType = contentType.split(/;/)[0] if contentType
        
        if soma.config.processBody == false
            @route()
        
        else
            switch contentType
                when 'application/x-www-form-urlencoded' then @_readUrlEncoded()
                when 'application/json' then @_readJSON()
                when 'application/octet-stream' then @_readBinary()
                when 'multipart/form-data' then @_readFormData()
                else @route()
        
        return
        
    route: () ->
        if not @_checkCSRF()
            return @sendError(null, 'Bad/missing CSRF token')
            
        results = soma.router.run(@pathname, @)
        if not results.length
            @send(404)

        return

    build: (body) ->
        @emit 'build', body
        html = """
            <!doctype html>
            <html #{@manifest or ''}>
            <head>
                #{(value for key, value of @head).join('\n    ')}
                
                <script type="text/javascript">
                    soma._initialViews = #{JSON.stringify(@views)};
                    soma.bundled = #{JSON.stringify(soma.bundled)};
                </script>
            </head>
            <body>
                #{body}
            </body>
            </html>
        """
        
        if @cookies.get('_csrf', {raw: true})
            @send(html)
            
        else
            crypto.randomBytes 32, (err, buf) =>
                throw err if err
                @cookies.set('_csrf', buf.toString('hex'), {raw: true})
                @send(html)
        
        return

    send: (statusCode, body, contentType) ->
        if typeof statusCode isnt 'number'
            contentType = body
            body = statusCode
            statusCode = 200
        
        body or= ''
        
        if body instanceof Buffer
            contentType or= 'application/octet-stream'
            contentLength = body.length
    
        else
            if typeof body is 'string'
                contentType or= 'text/html'
            else
                body = JSON.stringify(body)
                contentType or= 'application/json'
                
            contentLength = Buffer.byteLength(body)

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
        if @chunks
            for chunk in @chunks
                chunk.emit('halt')
                
            @chunks = null
            
        @response.statusCode = 303
        @response.setHeader('Location', path)
        @cookies.setHeaders()
        @response.end()
        return false

    _checkCSRF: ->
        token = @cookies.get('_csrf', {raw: true})
        
        if @request.method == 'GET'
            return true
        else if @body != null and @body._csrf == token
            delete @body._csrf
            return true
        else if @request.headers['x-csrf-token'] == token
            return true
        else
            return false
        
    _readJSON: ->
        chunks = []
        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', () =>
            @body = JSON.parse(chunks.join('') or 'null')
            @route()

        return
    
    _readBinary: ->
        chunks = []
        @body = {}

        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', =>
            @body[@request.headers['x-file-name']] = combineChunks(chunks)
            @route(data)
            
    _readUrlEncoded: ->
        chunks = []
        @request.on 'data', (chunk) => chunks.push(chunk)
        @request.on 'end', () =>
            @body = querystring.parse(chunks.join(''))
            @route()

        return
        
    _readFormData: ->
        chunks = []
        @body = {}

        formData = new multipart.formData(@request)
        
        formData.on 'stream', (stream) =>
            chunks = []
            stream.on 'data', (chunk) => chunks.push(chunk)
            stream.on 'end', () => @body[stream.name] = combineChunks(chunks)
        
        formData.on 'end', () =>
            delete @body._csrf
            @route(data)

        formData.begin()
        return

    setTitle: (title) ->
        return @loadElement 'title', {}, title

    setIcon: (attributes) ->
        if typeof attributes is 'string'
            attributes = { href: attributes }

        attributes.rel or= 'icon'
        attributes.type or= 'image/png'
        return @loadElement 'link', attributes

    setMetaHeader: (attributes, content) ->
        if typeof attributes is 'string'
            attributes = { 'http-equiv': attributes, content: content }

        return @loadElement 'meta', attributes

    setMeta: (attributes, content) ->
        if typeof attributes is 'string'
            attributes = { name: attributes, content: content }

        return @loadElement 'meta', attributes

    setManifest: (src) ->
        @addManifest(src)

    loadElement: (tag, attributes, text, callback) ->
        el = new Element(tag, attributes, text)
        @addHeadElement(el)

        callback(null, el) if callback
        return el
        
    loadFile: (url, callback) ->
        url = @resolve(url)

        if url of soma.files
            callback(null, soma.files[url])
        else
            callback(new Error("File '#{url}' could not be found"))
            
        return

    loadScript: (attributes, text, callback) ->
        if typeof text is 'function'
            callback = text
            text = null
            
        if typeof attributes is 'string'
            attributes = { src: attributes }
            
        attributes.type or= 'text/javascript'
        attributes.charset or= 'utf8'

        if attributes.src
            attributes.src = @resolve(attributes.src)
            
            if soma.config.inlineScripts and attributes.src of soma.files or attributes['type'] != 'text/javascript'
                text = soma.files[attributes.src]
                attributes['data-src'] = attributes.src
                delete attributes.src

            else
                # attributes['defer'] = 'defer'
                attributes['data-loading'] = 'loading'
                attributes['onload'] = "this.removeAttribute('data-loading');"

        @loadElement 'script', attributes, text, callback
        return

    loadStylesheet: (attributes, text, callback) ->
        if typeof text is 'function'
            callback = text
            text = null
            
        if typeof attributes is 'string'
            attributes = { href: attributes }

        if attributes.href
            attributes.href = @resolve(attributes.href)

            if soma.config.inlineStylesheets and attributes.href of soma.files
                tag = 'style'
                text = soma.files[attributes.href]
                attributes['data-href'] = attributes.href
                delete attributes.href
                
            else
                attributes.rel or= 'stylesheet'
                attributes.type or= 'text/css'
                attributes.charset or= 'utf8'
            
        tag = if attributes.href then 'link' else 'style'
        @loadElement tag, attributes, text, callback
        return

    loadImage: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.src = @resolve(attributes.src)
        attributes['data-loading'] = 'loading'
        attributes['onload'] = "this.removeAttribute('data-loading');"

        @loadElement 'img', attributes, null, callback
        return

    loadData: (options, callback) ->
        if typeof options is 'string'
            options = { url: options }

        options.url = @resolve(options.url)
        
        subcontext = @createSubcontext
            body: options.data
            begin: -> soma.router.run(options.url, @)

            send: (statusCode, body) ->
                if typeof statusCode isnt 'number'
                    body = statusCode
                    statusCode = 200

                if statusCode != 200
                    options.error(statusCode, body, options) if options.error
                    return callback(statusCode, body)

                options.success(body) if options.success
                callback(null, body)

            sendError: (err, body) ->
                console.log(err.stack) if err
                @send(500, body)

        subcontext.begin()
        return
        
