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
        
    constructor: (@tag, @attributes, @text) ->
        if tag in ['img', 'script']
            @url = attributes.src or attributes['data-src']
        else
            @url = attributes.href or attributes['data-href']

    toString: ->
        html = "<#{@tag}"
        for name, value of @attributes
            html += " #{name}=\"#{escapeXML(value)}\""
        
        html += if not @text and @isVoid() then ' />' else ">#{@text or ''}</#{@tag}>"
        return html


class soma.Chunk extends soma.Chunk
    loadScript: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.type = 'text/javascript'
        attributes.charset = 'utf8'

        if @context.inlineScripts
            text = soma.files[attributes.src]
            attributes['data-src'] = attributes.src
            delete attributes.src
            
        @context.addHeadElement(new Element('script', attributes, text))        
        callback() if callback
        return
        
    loadStylesheet: (attributes) ->
        if typeof attributes is 'string'
            attributes = { href: attributes }

        if @context.inlineStylesheets
            tag = 'style'
            text = soma.files[attributes.href]
            attributes['data-href'] = attributes.href
            delete attributes.href
            
        attributes.type = 'text/css'
        attributes.rel = 'stylesheet'
        attributes.charset = 'utf8'

        @context.addHeadElement(new Element('link', attributes, text))
        return

    loadTemplate: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        if @context.inlineTemplates
            text = soma.files[attributes.src]
            attributes['data-src'] = attributes.src
            delete attributes.src

        attributes.type = 'text/plain'
        attributes.charset = 'utf8'

        @context.addHeadElement(new Element('script', attributes, text))
        return text

    loadImage: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }
            
        return new Element('img', attributes)

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
    inlineTemplates: true
    inlineScripts: false
    inlineStylesheets: false
    
    constructor: (@request, @response) ->
        urlParsed = url.parse(@request.url, true)
        for key of urlParsed
            @[key] = urlParsed[key]

        @jar = new jar.Jar(@request, @response, ['$ecret']) # FIX THIS!
        @head = []
        @seen = {}
        
    addHeadElement: (element) ->
        return if element.url in @seen
        
        @seen[element.url] = true
        @head.push(element)
        return

    begin: () ->
        switch @request.headers['content-type']
            when undefined, 'application/x-www-form-urlencoded' then @_readUrlEncoded()
            when 'application/json' then @_readJSON()
            when 'application/octet-stream', 'multipart/form-data' then @_readFiles()
        
        return
        
    route: (@data) ->
        results = soma.router.run(@path, @)
        
        for result in results
            if result instanceof soma.Chunk
                @chunk = result
                @chunk.load(this)
                
            else if result instanceof soma.Page
                @page = result
        
        @render()

        return
        
    render: ->
        if @chunk
            @page or= new soma.pages.Default
            
            if @chunk.html
                @page.render(@chunk)
            else
                @chunk.on 'complete', => @page.render(@chunk)

        else
            @send(404)
        
    send: (statusCode, body, contentType) ->
        if typeof statusCode isnt 'number'
            contentType = body
            body = statusCode
            statusCode = 200
        
        body or= ''

        if body instanceof Buffer
            contentType or= 'application/octet-stream'
    
        else
            if typeof body is 'object'
                body = JSON.stringify(body)
                contentType or= 'application/json'
            else
                contentType or= 'text/html'

        @response.statusCode = statusCode
        @response.setHeader('Content-Type', contentType)
        @response.setHeader('Content-Length', Buffer.byteLength(body))
        @response.end(body)
        return
        
    sendError: (err, body) ->
        console.log(err.stack) if err
        @send(500, body)

    redirect: (path) ->
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

    redirect: (path) -> @parent.redirect(path)
    

