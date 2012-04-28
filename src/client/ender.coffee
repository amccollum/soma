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

    # just for fun?
    outerHTML: (html) ->
        if html then @each -> $(@).replaceWith(html)
        else @[0].outerHTML or new XMLSerializer().serializeToString(@[0])

}, true)

origin = document.location

$('document').ready ->
    window.onpopstate = () ->
        # ignore the popstate event on page-load in Safari and Chrome
        if document.location == origin
            origin = null
            return
            
        context = new soma.BrowserContext(document.location)
        context.begin()
        return
        
    $.enhance()



