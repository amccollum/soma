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

origin = document.location
soma.context = null

$('document').ready ->
    window.onpopstate = () ->
        # ignore the popstate event on page-load in Safari and Chrome
        if document.location == origin
            origin = null
            return
            
        soma.context = new soma.BrowserContext(document.location)
        soma.context.begin()
        return
        
    $.enhance()



