fs = require('fs')
path = require('path')
zlib = require('zlib')

mime = require('../lib/node/lib/mime')
soma = require('soma')

exports.load = ->
    soma.files = {}
    soma.tree = {}
    soma.bundles = {}
    soma.scripts = ['ender.js']

    loadFiles('ender.js', soma.tree, false)
        
    for source in soma.config.api
        loadFiles(source, soma.tree, true)

    for source in soma.config.app
        loadFiles(source, soma.tree, false)

    if fs.existsSync('bundles.json')
        soma.bundles = JSON.parse(fs.readFileSync('bundles.json'))
        
        
loadFiles = (source, tree, api) ->
    basename = path.basename(source)
    
    return if not fs.existsSync(source)
    
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
                
                loadFiles(path.join(source, name), tree[basename], api)                        

        watcher.emit('change')
        
    else
        abs = path.join(process.cwd(), source)
        url = "/#{source}"
        
        if basename.slice(-3) == '.js'
            if api or basename == '_init.js'
                soma._src = url
                require(abs)
                soma._src = null
                
            if not api and basename == '_init.js'
                soma.scripts.push(url)
        
        
        if not api
            if mime.lookup(source).slice(0, 4) in ['text']
                encoding = 'utf8'

            data = fs.readFileSync(source, encoding)
        
            tree[basename] = url
            soma.files[url] = data
        
    return


# buildDefaultRoutes = (tree) ->
#     result = {}
#     
#     for name, subtree of tree
#         if typeof subtree is 'object'
#             return buildRoutes(subtree)
#             
#         else if /// .chunk.js$ ///.test(name)
#             return subtree
# 
# 
# generateInit = (tree) -> """
#     require('soma').routes(#{JSON.stringify(buildDefaultRoutes(tree))});
#     """
# 
