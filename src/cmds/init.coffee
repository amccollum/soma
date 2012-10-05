fs = require('fs')

soma = require('soma')

exports.init = ->
    defaults =
        compress: true
        inlineScripts: false
        inlineStylesheets: false
        
        app: ['app']
        api: ['api']

    soma.config = JSON.parse(fs.readFileSync('package.json')).soma
    
    for key, value of defaults
        if key not of soma.config
            soma.config[key] = value

    