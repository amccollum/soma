cmds = 
    init: require('../cmds/init').init
    bundle: require('../cmds/bundle').bundle
    load: require('../cmds/init').load
    run: require('../cmds/run').run

cmds.init()

switch process.argv[2]
    when 'bundle'
        cmds.load()
        cmds.bundle()
        
    when 'run', null
        cmds.load()
        cmds.run()
