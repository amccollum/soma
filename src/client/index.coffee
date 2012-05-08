jar = require('jar')
soma = require('soma')


class soma.Chunk extends soma.Chunk
    complete: ->
        @el or= $(@html)
        @el.data('view', @)
                    
    loadElement: (tag, attributes, text, callback) ->
        urlAttr = (if tag in ['img', 'script'] then 'src' else 'href')
        url = attributes[urlAttr]
        
        # Check if the element is already loaded (or has been pre-fetched)
        el = $("head [#{urlAttr}=\"#{url}\"], head [data-#{urlAttr}=\"#{url}\"]") if url

        if el.length
            # See whether the element was lazy-loaded
            if 'type' of attributes and attributes.type != el.attr('type')
                el.detach().attr('type', attributes.type).appendTo($('head'))

        else
            # Element hasn't been created yet
            el = $(document.createElement(tag))
            
            if 'type' of attributes
                if not url
                    # The element content is inline
                    el.text(text)
                    
                else if attributes.type == 'text/javascript'
                    el.attr('async', 'async')
                
                else
                    # Load manually using AJAX
                    el.attr("data-#{urlAttr}", url)
                    delete attributes[urlAttr]

                    $.ajax
                        method: 'GET'
                        url: "#{url}"
                        type: 'html'

                        success: (text) =>
                            el.text(text)
                            el.trigger('load')

                        error: (xhr, status, e, data) =>
                            el.trigger('error')

                $('head').append(el)

            # We don't need to load dataURLs
            if url and url.substr(0, 5) != 'data:'
                el.attr('data-loading', 'loading')
                el.bind 'load error', => el.removeAttr('data-loading')
                
            el.attr(attributes)

        if el.attr('data-loading')
            done = @wait(callback)
            el.bind 'load', =>
                done(el)
                
            el.bind 'error', () =>
                @emit('error', 'loadElement', tag, attributes, text)
                done(el)
                
        else if callback
            callback(el)

        return el

    setTitle: (title) ->
        $('title').text(title)
    
    setMeta: (attributes, value) ->
        if typeof attributes is 'string'
            name = attributes
            attributes = { name: name, value: value }

        el = $("meta[name=\"#{attributes.name}\"]")
        if not el.length
            el = $(document.createElement('meta'))
            $('head').append(el)

        el.attr(attributes)
        return el
        
    loadScript: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.type = 'text/javascript'
        return @loadElement 'script', attributes, null, callback
        
    loadStylesheet: (attributes) ->
        if typeof attributes is 'string'
            attributes = { href: attributes }

        attributes.type = 'text/css'
        attributes.rel = 'stylesheet'
        return @loadElement 'link', attributes
        
    loadTemplate: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }
        
        attributes.type = 'text/html'
        el = @loadElement 'script', attributes
        el.toString = -> el.html()
        return el

    loadImage: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }
            
        el = @loadElement 'img', attributes
        el.toString = -> el.outerHTML()
        return el
    
    loadData: (options) ->
        result = {}

        options.method or= 'GET'
        options.type = 'json'
        options.headers or= {}
        
        if options.data and typeof options.data isnt 'string'
            options.headers['Content-Type'] = 'application/json'
            options.data = JSON.stringify(options.data)
            
        done = @wait()
        _success = options.success
        _error = options.error
        
        options.success = (data) =>
            for key in data
                result[key] = data[key]

            _success(data) if _success
            done()
            
        options.error = (xhr) =>
            if _error
                _error(xhr.status, xhr.response, options)
            else
                @emit('error', 'requireData', xhr.status, xhr.response, options)

            done()
        
        $.ajax(options)

        return result


class soma.BrowserContext extends soma.Context
    constructor: (@path, @lazy) ->
        @cookies = jar.jar

    begin: ->
        results = soma.router.run(@path, @)
        if not results.length
            throw new Error('No routes matched')

        else
            for result in results
                if result instanceof soma.Chunk
                    @send(result)
        
        return

    send: (chunk) ->
        if chunk not instanceof soma.Chunk
            throw new Error('Must send chunks')
        else if @chunk
            throw new Error('Cannot send multiple chunks')
        
        @chunk = chunk
        while @chunk.meta
            @chunk = @chunk.meta()

        @chunk.load(this)
        @render() if not @lazy
        return
        
    render: ->
        if not @chunk
            throw new Error('No chunk loaded')
        
        fn = =>
            @chunk.emit('render')
            $('body').html(@chunk.html)
            
        if @chunk.html then fn() else @chunk.on 'complete', fn
        return

    go: (path, replace) ->
        if history.pushState
            if replace
                history.replaceState({}, "", path)
            else
                history.pushState({}, "", path)
                window.onpopstate()

        else
            # if we don't have pushState, we need to load a new Chunk
            document.location = path
    
        return

