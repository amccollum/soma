jar = require('jar')
soma = require('soma')


class soma.Chunk extends soma.Chunk
    complete: ->
        @el or= $(@html)
        @el.data('view', @)
                    
    loadElement: (tag, attributes) ->
        urlAttr = (if tag in ['img', 'script'] then 'src' else 'href')
        url = attributes[urlAttr]
        
        # Check if the element is already loaded (or has been pre-fetched)
        el = $("[#{urlAttr}=\"#{url}\"], [data-#{urlAttr}=\"#{url}\"]")

        if el.length
            # See whether the element was lazy-loaded
            if 'type' of attributes and attributes.type != el.attr('type')
                el.detach().attr('type', attributes.type).appendTo($('head'))

        else
            # Element hasn't been created yet
            el = $(document.createElement(tag))
                
            if 'type' of attributes
                if attributes.type == 'text/javascript'
                    el.attr('async', 'async')
                    
                else if attributes.type != 'text/css'
                    # Load manually using AJAX
                    el.attr("data-#{urlAttr}", url)

                    $.ajax
                        method: 'GET'
                        url: "#{url}?#{Math.random()}"
                        type: 'html'

                        success: (text) =>
                            el.text(text)
                            el.trigger('load', text)

                        error: (xhr, status, e, data) =>
                            el.trigger('error')

                $('head').append(el)

            # We don't need to load dataURLs
            if url.substr(0, 5) != 'data:'
                el.attr('data-loading', 'loading')

            el.attr(attributes)

        if el.attr('data-loading') 
            done = @wait()
            el.bind 'load', =>
                el.attr('data-loading', null)
                done()
                
            el.bind 'error', () =>
                el.attr('data-loading', null)
                @emit('error', 'requireElement', tag, attributes)
                done()

        return el

    loadScript: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.type = 'text/javascript'
        return @loadElement 'script', attributes
        
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
        return @loadElement 'script', attributes

    loadImage: (attributes) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }
            
        return @loadElement 'img', attributes
    
    loadData: (options) ->
        result = {}

        options.method or= 'GET'
        options.type = 'json'
        options.headers or= {}
        
        if options.data and typeof options.data isnt 'string'
            options.headers['Content-Type'] = 'application/json'
            options.data = JSON.stringify(options.data)
            
        done = wait()
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
    constructor: (@url, @lazy) ->
        @jar = jar.jar

    begin: ->
        results = soma.router.run(@path, @)
        
        for result in results
            if result instanceof soma.Chunk
                @chunk = result
                @chunk.load(this)
            else if result instanceof soma.Page
                @page = result
        
        if not @lazy
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
            throw "Every route needs to return both a chunk and a page"


