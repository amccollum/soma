soma = require('soma')
$ = ender


# Ender additions
$.ender({
    enhance: (context) -> $(document).enhance(context)
})

$.ender({
    enhance: (context) ->
        views = []
        for own name, value of soma.views
            $(value::selector, @).each ->
                views.push(new soma.views[name]({el: @, context: context}))
        
        for view in views
            view.emit('complete')

        for form in $('form')
            $(form).append("<input type=\"hidden\" name=\"_csrf\" value=\"#{$.jar.get('_csrf', {raw:true})}\" />")

        return

    # just for fun?
    outerHTML: (html) ->
        if html then @each -> $(@).replaceWith(html)
        else @[0].outerHTML or new XMLSerializer().serializeToString(@[0])

}, true)

$('document').ready ->
    # We already have the HTML, but we need a context to create the views
    context = new soma.BrowserContext(document.location.pathname)
    $.enhance(context)
    
    # Implement client-side loading and precaching, when possible
    if history.pushState
        
        # This is to fix browsers that call popstate on page load
        $('document').one 'load', -> history.replaceState(true, '', document.location)

        window.onpopstate = (event) ->
            # Don't do anything if this was a page load
            if not event.state
                return
            
            soma.load(document.location.pathname)
        
        $('a[data-precache != "true"]:local-link(0)').each ->
            path = @pathname

            $(@).bind 'click', (event) ->
                history.pushState(true, '', path)
                soma.load(path)
                event.stop()
                return
            
        $('a[data-precache = "true"]:local-link(0)').each ->
            $(@).bind 'click', soma.precache(@pathname)
            return


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
    context = new soma.BrowserContext(path, lazy)
    context.begin()
    return context
    

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
    
    setIcon: (attributes) ->
        if typeof attributes is 'string'
            attributes = { href: attributes }

        attributes.rel or= 'icon'
        attributes.type or= 'image/png'

        el = $("link[rel=\"#{attributes.rel}\"][href=\"#{attributes.href}\"]")
        if not el.length
            el = $(document.createElement('link'))
            $('head').append(el)

        el.attr(attributes)
        return el

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

        done = @wait()
        _success = options.success
        _error = options.error
        
        options.headers or= {}
        options.headers['X-CSRF-Token'] = @cookies.get('_csrf', {raw: true})

        options.success = (data) =>
            for key in data
                result[key] = data[key]

            _success(data) if _success
            done()
            
        options.error = (xhr) =>
            if _error
                _error(xhr.status, xhr.response, options)
            else
                @emit('error', 'loadData', xhr.status, xhr.response, options)

            done()

        $.ajaj(options)

        return result


class soma.BrowserContext extends soma.Context
    constructor: (@path, @lazy) ->
        @cookies = $.jar

    begin: ->
        @results = soma.router.run(@path, @)

        if @results and @results.length
            for result in @results
                if result instanceof soma.Chunk
                    @send(result)
                    
        else
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
        
    render: ->
        @lazy = false
        
        if not @chunk
            document.location = @path
            return
        
        done = =>
            @chunk.emit('render')
            $('body').html(@chunk.html)
            $.enhance(@)
            
        if @chunk.status is 'complete' then done() else @chunk.on 'complete', done
        return

    go: (path, replace) ->
        if history.pushState
            if not @lazy
                if replace
                    history.replaceState(true, '', path)
                else
                    history.pushState(true, '', path)

            if @chunk
                @chunk.emit('halt')
                @chunk = null
                
            @path = path
            @begin()

        else
            # if we don't have pushState, we need to load a new Chunk
            document.location = path
    
        return
