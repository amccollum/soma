crypto = require('crypto')
domain = require('domain')
http = require('http')
fs = require('fs')
path = require('path')

mime = require('../lib/node/lib/mime')
soma = require('soma')

Line = require('line').Line

loadFiles = (source, api, tree={}, files={}, callback) ->
    basename = path.basename(source)
    
    if fs.statSync(source).isDirectory()
        watcher = fs.watch source, ->
            if not path.existsSync(source)
                console.log('Directory went missing: ', source)
                delete tree[basename]
                watcher.close()
                return

            tree[basename] = {}
        
            for name in fs.readdirSync(source)
                if name[0] == '.'
                    continue
                
                loadFiles "#{source}/#{name}", api, tree[basename], files={}, line.wait()
                        

        watcher.emit('change')
        
    else
        abs = "#{process.cwd()}/#{source}"
        url = "/#{source}"
        
        if name.slice(-3) == '.js'
            if api or name == '_init.js'
                soma._src = url
                require(abs)
                soma._src = null
                
            if not api and name == '_init.js'
                soma.scripts.push(url)
        
        if not api
            if mime.lookup(source).slice(0, 4) in ['text']
                encoding = 'utf8'

            data = fs.readFileSync(source, encoding)
        
            tree[basename] = url
            files[url] = data
        
    return
    

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
    soma.files = {}
    soma.tree = {}
    soma.bundles = {}
    soma.scripts = ['ender.js']
    
    for key, value of require('./package.json').soma
        soma.config[key] = value
        
    soma.config.api or= 'api'
    soma.config.app or= 'app'

    
    loadFiles(soma.config.api, true, soma.tree, soma.files)
    loadFiles(soma.config.app, false, soma.tree, soma.files)
    loadFiles('bundles', soma.tree, soma.files)
    
    soma.bundled = require('./bundles')
    
    
soma.init = ->
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
                    context = new soma.Context(request, response, soma.scripts)
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