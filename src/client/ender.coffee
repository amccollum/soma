soma = require('soma')
$ = ender

soma.config.engine = 'browser'

# Ender additions
$.ender
    enhance: -> $(document).enhance()
    ajaj: (options) ->
        options.method or= 'GET'
        options.type = 'json'

        options.headers or= {}
        options.headers['X-CSRF-Token'] = @cookies.get('_csrf', {raw: true})
        options.headers['Content-Type'] = 'application/json'
    
        if options.data and typeof options.data isnt 'string'
            options.data = JSON.stringify(options.data)
            
        return $.ajax(options)

$.ender({
    enhance: ->
        $('a[data-precache != "true"]:local-link(0)', @).each ->
            path = @pathname

            $(@).bind 'click', (event) ->
                history.pushState(true, '', path)
                soma.load(path)
                event.stop()
                return
            
        $('a[data-precache = "true"]:local-link(0)', @).each ->
            $(@).bind 'click', soma.precache(@pathname)
            return

    outerHTML: (html) ->
        if html then @each -> $(@).replaceWith(html)
        else @[0].outerHTML or new XMLSerializer().serializeToString(@[0])

}, true)


$('document').ready ->
    # We already have the HTML, but we need a context to create the views
    context = new soma.Context(document.location.pathname)
    context.views = soma._initialViews
    conext.emit('render')
    
    # Implement client-side loading and precaching, when possible
    if history.pushState
        
        # This is to fix browsers that call popstate on page load
        $('document').one 'load', -> history.replaceState(true, '', document.location)

        window.onpopstate = (event) ->
            # Don't do anything if this was a page load
            if not event.state
                return
            
            soma.load(document.location.pathname)
        

soma.precache = (path) ->
    if history.pushState
        context = soma.load(path, true)
        return (event) ->
            history.pushState({}, '', context.path)
            context.render()
            event.stop() if event
            return
            
    else
        return (event) ->
            # only use doc.location if the path is different
            if @pathname != path
                document.location = path
                event.stop() if event


soma.load = (path, lazy) ->
    context = new soma.Context(path, lazy)
    context.begin()
    return context
    

class soma.Context extends soma.Context
    constructor: (@path, @lazy) ->
        super
        @cookies = $.jar
        @child = null
        @built = false
        @rendered = false
        @stopped = false
        
        @on 'render', =>
            $.enhance()
            
            context = @
            for url in @views
                @loadCode url, ['soma'], (err, fn) ->
                    throw err if err            
                    fn.apply(context, soma)
                    return

    begin: ->
        @results = soma.router.run(@path, @)
        @render() if not @lazy
        
        return

    send: (chunk) ->
        if chunk not instanceof soma.Chunk
            throw new Error('Must send chunks on the client')
        else if @chunk
            throw new Error('Cannot send multiple chunks')
        
        @chunk = chunk
        while @chunk.meta
            @chunk = @chunk.meta()

        @chunk.load(this)
        @render() if not @lazy
        return
    
    build: (@html) ->
        @built = true
        @emit 'build', @html
        return
        
    render: ->
        return @child.render() if @child
            
        @lazy = false
        
        # If we didn't execute any routes, go to the server
        if not @results.length
            document.location = @path
            return 
        
        done = =>
            if not @stopped
                $('body').unbind().html(@html)
                @rendered = true
                @emit('render')
            
        if @html then done() else @on 'build', done
        return
        
    go: (path, replace) ->
        if history.pushState
            if not @lazy
                if replace
                    history.replaceState(true, '', path)
                else
                    history.pushState(true, '', path)

            @stopped = true
            @child = new soma.Context(path, @lazy)
            @child.begin()

        else
            # if we don't have pushState, we need to load a new Chunk
            document.location = path
    
        return
        
    setTitle: (title) ->
        if not @rendered
            @on 'render', => @setTitle(title)
        else
            $('title').text(title)
            
        return

    setIcon: (attributes) ->
        if not @rendered
            @on 'render', => @setIcon(attributes)
        else
            if typeof attributes is 'string'
                attributes = { href: attributes }

            attributes.rel or= 'icon'
            attributes.type or= 'image/png'

            el = $("link[rel=\"#{attributes.rel}\"][href=\"#{attributes.href}\"]")
            if not el.length
                el = $(document.createElement('link'))
                $('head').append(el)

            el.attr(attributes)
            
        return

    setMeta: (nameOrAttributes, value) ->
        if not @rendered
            @on 'render', => @setMeta(attributes, value)
        else
            if value
                attributes = { name: nameOrAttributes, value: value }
            else
                attributes = nameOrAttributes
                
            el = $("meta[name=\"#{attributes.name}\"]")
            if not el.length
                el = $(document.createElement('meta'))
                $('head').append(el)

            el.attr(attributes)

        return

    loadElement: (tag, attributes, text, callback) ->
        urlAttr = (if tag in ['img', 'script'] then 'src' else 'href')
        url = attributes[urlAttr]

        # Check if the element is already loaded (or has been pre-fetched)
        el = $("head [#{urlAttr}=\"#{url}\"], head [data-#{urlAttr}=\"#{url}\"]") if url

        if el and el.length
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
                    el.attr('defer', 'defer')

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

                        error: (xhr) =>
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

    loadFile: (url, callback) ->
        url = @resolve(url)
        
        if url of soma.bundled
            sha = soma.bundled[url]
            attributes =
                src: "/bundles/#{sha}.js"
                type: 'text/javascript'
        
            @loadElement 'script', attributes, null, (err) ->
                return callback.apply(this, arguments) if err
                callback(null, soma.bundles[sha][url])
        
        else
            attributes =
                src: url
                type: 'text/plain'
        
            @loadElement 'script', attributes, null, (err, el) ->
                return callback.apply(this, arguments) if err
                callback(null, el.text())
        
        return

    loadScript: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.src = @resolve(attributes.src)
        attributes.type = 'text/javascript'
        @loadElement 'script', attributes, null, callback
        return

    loadStylesheet: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { href: attributes }

        attributes.href = @resolve(attributes.href)
        attributes.type = 'text/css'
        attributes.rel = 'stylesheet'
        @loadElement 'link', attributes, null, callback
        return

    loadImage: (attributes, callback) ->
        if typeof attributes is 'string'
            attributes = { src: attributes }

        attributes.src = @resolve(attributes.src)
        @loadElement 'img', attributes, null, callback
        el.toString = -> el.outerHTML()
            
        return

    loadData: (options, callback) ->
        _success = options.success
        _error = options.error

        options.url = @resolve(options.url)

        options.success = (data) =>
            _success(data) if _success
            callback(null, data)

        options.error = (xhr) =>
            _error(xhr.status, xhr.response, options) if _error
            callback(xhr.status, xhr.response, options, xhr)

        $.ajaj(options)
        return
