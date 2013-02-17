fs = require('fs')

soma = require('soma')

exports.init = ->
    soma.config =
        compress: true
        inlineScripts: false
        inlineStylesheets: false
        
        app: ['app']
        api: ['api']

    packageJSON = require(process.cwd() + '/package')
    
    for key, value of packageJSON.soma
        soma.config[key] = value

    # for dep of packageJSON.dependencies
    #     try
    #         if 'soma' in require(dep + '/package').keywords
    #             require(dep)
    #     catch e
    #         console.log(e)
    #         continue
            
    return