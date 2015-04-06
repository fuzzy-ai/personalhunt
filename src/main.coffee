debug = require('debug')('personalhunt')

newApp = require('./app')

config =
  port: process.env.PORT or 80

newApp config, (err, app) ->
  if err
    debug 'Error: ' + err.message
    process.exit -1
  else
    server = app.listen app.get('port'), ->
      debug 'Express server listening on port ' + server.address().port
