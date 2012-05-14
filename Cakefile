fs = require('fs')
{spawn, exec} = require('child_process')

execCmds = (cmds) ->
    exec cmds.join(' && '), (err, stdout, stderr) ->
        output = (stdout + stderr).trim()
        console.log(output + '\n') if (output)
        throw err if err

task 'build', 'Compile to JS', ->
    execCmds [
        'coffee --compile --output lib src/*.coffee'
        
        'coffee --compile --bare --output lib/node/lib src/node/lib/*.coffee'
        'coffee --compile --bare --output lib/node src/node/*.coffee'

        'coffee --compile --bare --output lib/client src/client/*.coffee'
        
        'mkdir -p bin'
        'echo "#!/usr/bin/env node" > bin/soma'
        'coffee --compile --bare --print src/bin/soma.coffee >> bin/soma'
        'chmod u+x bin/soma'
    ]
