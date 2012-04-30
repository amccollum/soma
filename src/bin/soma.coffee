http = require('http')
fs = require('fs')
path = require('path')

mime = require('../lib/node/lib/mime')
soma = require('soma')

load = (source, exec, serve) ->
    stats = fs.statSync(source)
    
    if stats.isDirectory()

        names = fs.readdirSync(source)
    
        for name in names
            load("#{source}/#{name}", exec, serve) if name[0] != '.'
            
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
                    if mime.lookup(source).slice(0, 4) in ['text', 'appl']
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


soma.init = () ->
    soma.files = {}
    
    packageJSON = JSON.parse(fs.readFileSync('package.json'))

    for source in packageJSON.soma.shared
        load(path.normalize(source), true, true)

    for source in packageJSON.soma.server
        load(path.normalize(source), true, false)

    for source in packageJSON.soma.client
        load(path.normalize(source), false, true)

    server = http.createServer (request, response) ->
        if request.url of soma.files
            response.setHeader('Content-Type', mime.lookup(request.url))
            response.end(soma.files[request.url])
            
        else
            context = new soma.ClientContext(request, response)
            context.begin()

    server.listen(packageJSON.soma.port or 8000)
    console.log("Soma listening on port #{packageJSON.soma.port or 8000}...")

soma.init()