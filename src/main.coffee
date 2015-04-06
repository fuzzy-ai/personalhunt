debug = require('debug')('personalhunt')

newApp = require('./app')

config =
  port: process.env.PORT or 80
  driver: process.env.DRIVER or "mongodb"
  params: if process.env.PARAMS then JSON.parse(process.env.PARAMS) else {}

newApp config, (err, app) ->
  if err
    debug 'Error: ' + err.message
    process.exit -1
  else
    server = app.listen app.get('port'), ->
      debug 'Express server listening on port ' + server.address().port
