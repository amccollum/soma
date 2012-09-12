crypto = require('crypto')
domain = require('domain')
http = require('http')
fs = require('fs')
path = require('path')

mime = require('../lib/node/lib/mime')
soma = require('soma')

Line = require('line').Line

loadFiles = (source, tree={}, files={}, callback) ->
    basename = path.basename(source)
    
    if fs.statSync(source).isDirectory()
        watcher = fs.watch source, ->
            if not path.existsSync(source)
                console.log('Directory went missing: ', source)
                delete tree[basename]
                watcher.close()
                return

            tree[basename] = {}
        
            l = new Line
                error: (err) -> throw err

                -> fs.readdir(source, line.wait())

                (names) ->
                    for name in names
                        if name[0] == '.'
                            continue

                        loadFiles("#{source}/#{name}", tree[basename], files={}, line.wait())
                        
                -> callback(tree)

        watcher.emit('change')

    else
        abs = "#{process.cwd()}/#{source}"
        url = "/#{source}"
        
        if mime.lookup(source).slice(0, 4) in ['text']
            encoding = 'utf8'
        
        fs.readFile source, encoding, (err, data) ->
            return callback.apply(@, arguments) if err
            
            tree[basename] = url
            files[url] = data
            
            callback(null, tree)
            return
        
    return

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


class Bundle
    constructor: (sources) ->
        @files = {}
        @hash = null
        
        @collect(sources, soma.tree)
        
    hash: ->
        sha = crypto.createHash('sha1')
        
        for url, data of @files
            sha.update(url)
            sha.update(data)
            
        @hash = sha.digest('hex')
        return
        
    collect: (sources, tree) ->
        for source in sources
            parts = source.split('/')
        
            branch = tree
            for part in parts
                if part not of branch
                    branch = null
                    break
                
                branch = branch[part]
            
            if typeof branch is 'object'
                bundle(branch, branch, files)
            
            else
                @files[branch] = soma.files[branch]

        return
                
    write: (dir, callback) ->
        data = """
            soma.bundles['#{@hash}'] = #{JSON.stringify(@files)};
        """
         
        fs.writeFile "#{dir}/#{@hash}.js", data, 'utf8', callback
        return
        

soma.load = ->
    soma.config = require('./package.json')
    soma.config.chunks or= 'chunks'
    soma.config.templates or= 'templates'

    soma.files = {}
    soma.tree = {}
    soma.bundles = {}
    
    loadFiles(soma.config.chunks, soma.tree, soma.files)
    loadFiles(soma.config.templates, soma.tree, soma.files)
    loadFiles('bundles', soma.tree, soma.files)
    
    soma.bundled = require('./bundles')
    
    
soma.init = ->
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


if process.argv[2] == 'bundle'
    soma.load()
    
    bundles = {}
    mapping = {}
    
    for sources in soma.config.bundles
        bundle = new Bundle(sources)
        
        bundle.write 'bundles', (err) ->
            throw err if err

        bundles[bundle.hash] = bundle
        for url of bundles.files
            mapping[url] = bundle.hash
        
    data = """
        module.exports = #{JSON.stringify(mapping)};
    """
     
    fs.writeFile "#{dir}/index.js", data, 'utf8', (err) ->
        throw err if err
    
else    
    soma.load()
    soma.init()