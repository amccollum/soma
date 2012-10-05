domain = require('domain')
http = require('http')
fs = require('fs')
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

            requestDomain.run ->
                if request.url of soma.files
                    content = soma.files[request.url]
                    contentEncoding = 'identity'

                    send = (err, content) ->
                        throw err if err
                        
                        if typeof content is 'string'
                            contentLength =  Buffer.byteLength(content)
                        else
                            contentLength = content.length
                        
                        response.setHeader('Content-Type', mime.lookup(request.url))
                        response.setHeader('Content-Length', contentLength)
                        response.setHeader('Content-Encoding', contentEncoding)
                        response.end(content)

                    acceptEncoding = request.headers['accept-encoding'] or ''
                    if soma.config.compress and (m = acceptEncoding.match(/\b(deflate|gzip)\b/))
                        contentEncoding = m[1]
                        
                        if request.url in zlibCache[contentEncoding]
                            send(null, zlibCache[contentEncoding][request.url])
                        else
                            zlib[contentEncoding](content, send)

                    else
                        sendContent(null, content)
           
                else
                    context = new soma.Context(request, response, soma.scripts)
                    context.begin()

        port = process.env.PORT or soma.config.port or 8000
        server.listen(port)
        console.log("Soma listening on port #{port}...")
