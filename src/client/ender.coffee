soma = require('soma')
$ = ender

$.ender({
    view: (name, options) -> new soma.views[name](options)
    enhance: -> $(document).enhance()
})

$.ender({
    view: (name, options={}) ->
        @each ->
            options.el = @
            $.view(name, options)
            
    enhance: ->
        for own name, value of soma.views
            $(value::selector, @).view(name)
        
        return

    # just for fun?
    outerHTML: (html) ->
        if html then @each -> $(@).replaceWith(html)
        else @[0].outerHTML or new XMLSerializer().serializeToString(@[0])

}, true)

origin = document.location.pathname
soma.context = new soma.BrowserContext(origin)

$('document').ready ->
    if history.pushState
        window.onpopstate = () ->
            # ignore the popstate event on page-load in Safari and Chrome -- right now this doesn't work
            path = document.location.pathname
            if path == origin
                origin = null
                return
            
            soma.context = new soma.BrowserContext(path)
            soma.context.begin()
            return
        
        $('a:local-link(0)[data-precache != "true"]').each ->
            path = @pathname

            $(@).bind 'click', (event) ->
                history.pushState({}, "", path)
                window.onpopstate()
                event.stop()
                return
            
        $('a:local-link(0)[data-precache = "true"]').each ->
            path = @pathname
            context = new soma.BrowserContext(path, true)
            context.begin()
        
            $(@).bind 'click', (event) ->
                history.pushState({}, "", path)
                context.render()
                event.stop()
                return
                
    $.enhance()

