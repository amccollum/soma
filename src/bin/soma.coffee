domain = require('domain')
http = require('http')
fs = require('fs')
path = require('path')

mime = require('../lib/node/lib/mime')
soma = require('soma')

loadFiles = (source, tree={}) ->
    if fs.statSync(source).isDirectory()
        watcher = fs.watch source, ->
            if not path.existsSync(source)
                console.log('Directory went missing: ', source)
                delete tree[basename]
                watcher.close()
                return

            for name in fs.readdirSync(source)
                if name[0] == '.'
                    continue

                tree[name] = loadFiles("#{source}/#{name}")

        watcher.emit('change')
        return tree

    else
        abs = "#{process.cwd()}/#{source}"
        url = "/#{source}"
        
        soma.files[url] = fs.readFileSync(source, encoding)
        return url

load = (source, exec, serve) ->
    stats = fs.statSync(source)
    
    if stats.isDirectory()

        urls = []
        names = fs.readdirSync(source)

        for name in names
            if name[0] == '.'
                continue
                
            urls = urls.concat(load("#{source}/#{name}", exec, serve))
        
        return urls
        
    else
        abs = "#{process.cwd()}/#{source}"
        url = "/#{source}"
        
        if url in soma.files
            return
            
        watcher = fs.watch source, ->
            if not path.existsSync source
                console.log('Module went missing: ', source)
                watcher.close()
                return
                
            try
                if serve
                    if mime.lookup(source).slice(0, 4) in ['text']
                        encoding = 'utf8'

                    soma.files[url] = fs.readFileSync(source, encoding)

            catch e
                console.log('Failed to reload module: ', source)
                console.log(e.stack)
    

        watcher.emit('change')

        if exec and source.slice(-3) == '.js'
            # This so we can store the source file of chunk and view subclasses defined in the module
            soma._src = url
            m = require(abs)
            soma._src = null
            
        return [url]


soma.init = () ->
    soma.files = {}
    
    soma.config = JSON.parse(fs.readFileSync('package.json')).soma
    soma.config.chunks or= 'chunks'

    soma.tree = {}
    loadFiles(soma.config.chunks, soma.tree)
    
    if soma.config.templates
        loadFiles(soma.config.templates, soma.tree)
    
    for source in soma.config.shared
        load(path.normalize(source), true, true)

    for source in soma.config.server
        load(path.normalize(source), true, false)

    for source in soma.config.client
        load(path.normalize(source), false, true)

    scripts = []
    for source in soma.config.init
        scripts = scripts.concat(load(path.normalize(source), false, true))

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
                    contentType = mime.lookup(request.url)
                    content = soma.files[request.url]
            
                    if content instanceof Buffer
                        contentLength = content.length
                    else
                        contentLength = Buffer.byteLength(content)
            
                    response.setHeader('Content-Type', contentType)
                    response.setHeader('Content-Length', contentLength)
                    response.end(content)
            
                else
                    context = new soma.ClientContext(request, response, scripts)
                    context.begin()

        port = process.env.PORT or soma.config.port or 8000
        server.listen(port)
        console.log("Soma listening on port #{port}...")

soma.init()