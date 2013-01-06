crypto = require('crypto')
fs = require('fs')

soma = require('soma')

exports.bundle = ->
    bundles = {}
    mapping = {}
    
    fs.mkdirSync('bundles', 0o0700)
    
    for sources in soma.config.bundles
        if typeof sources is 'string'
            sources = [sources]
        
        bundle = new Bundle(sources)
        
        bundle.write('bundles')

        bundles[bundle.hash] = bundle
        for url of bundles.files
            mapping[url] = bundle.hash
        
    fs.writeFileSync('bundles.json', JSON.stringify(mapping), 'utf8')
    return


class Bundle
    constructor: (sources) ->
        @files = {}
        @hash = null
        
        @_collect(sources, soma.tree)

        sha = crypto.createHash('sha1')
        for url, data of @files
            sha.update(url)
            sha.update(data)
            
        @hash = sha.digest('hex')
        
    _collect: (sources, tree) ->
        for source in sources
            parts = source.split('/')
        
            branch = tree
            for part in parts
                if part not of branch
                    branch = null
                    break
                
                branch = branch[part]
            
            if typeof branch is 'object'
                @collect(branch, branch, files)
            
            else
                @files[branch] = soma.files[branch]

        return
                
    write: (dir) ->
        data = """
            soma.bundles['#{@hash}'] = #{JSON.stringify(@files)};
        """        
         
        fs.writeFileSync("#{dir}/#{@hash}.js", data, 'utf8')
        return
        
