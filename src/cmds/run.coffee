domain = require('domain')
http = require('http')
fs = require('fs')
url = require('url')
zlib = require('zlib')

mime = require('../lib/node/lib/mime')
soma = require('soma')

exports.run = ->
    zlibCache = {gzip: {}, deflate: {}}
    
    serverDomain = domain.create()
    serverDomain.run ->
        server = http.createServer (request, response) ->
            requestDomain = domain.create()
            requestDomain.add(request)
            requestDomain.add(response)            
            requestDomain.on 'error', (err) ->
                console.error('Error', request.url, err?.stack or err)

                try
                    response.statusCode = 500
                    response.end('Error occurred, sorry.')
                    response.on 'close', -> requestDomain.dispose()
                    
                catch err
                    console.error('Error sending 500', request.url, err)
                    requestDomain.dispose()
                    
                return

            requestDomain.run ->
                pathname = url.parse(request.url).pathname
                
                if pathname of soma.files
                    content = soma.files[pathname]
                    contentEncoding = 'identity'

                    send = (err, content) ->
                        throw err if err
                        
                        if contentEncoding != 'identity'
                            zlibCache[contentEncoding][pathname] = content
                        
                        if typeof content is 'string'
                            contentLength =  Buffer.byteLength(content)
                        else
                            contentLength = content.length
                        
                        response.setHeader('Content-Type', mime.lookup(pathname))
                        response.setHeader('Content-Length', contentLength)
                        response.setHeader('Content-Encoding', contentEncoding)
                        response.end(content)
                        return

                    acceptEncoding = request.headers['accept-encoding'] or ''
                    if soma.config.compress and (m = acceptEncoding.match(/\b(deflate|gzip)\b/))
                        contentEncoding = m[1]
                        
                        if pathname in zlibCache[contentEncoding]
                            send(null, zlibCache[contentEncoding][pathname])
                        else
                            zlib[contentEncoding](content, send)

                    else
                        sendContent(null, content)
           
                else
                    context = new soma.Context(request, response, soma.scripts)
                    context.begin()
                    
                return

        port = process.env.PORT or soma.config.port or 8000
        server.listen(port)
        console.log("Soma listening on port #{port}...")

        return
        
    return
