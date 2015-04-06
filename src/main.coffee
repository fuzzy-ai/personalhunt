newApp = require('./app')

config =
  port: process.env.PORT or 80
  key: process.env.KEY
  cert: process.env.CERT
  hostname: process.env.HOSTNAME
  address: process.env.ADDRESS or '0.0.0.0'
  driver: process.env.DRIVER or "mongodb"
  params: if process.env.PARAMS then JSON.parse(process.env.PARAMS) else {}
  clientID: process.env.CLIENT_ID
  clientSecret: process.env.CLIENT_SECRET

console.log "Creating app..."

newApp config, (err, app) ->
  if err
    console.log 'Error: ' + err.message
    process.exit -1
  else
    console.log "App created. Starting..."
    app.start ->
      console.log "Express server listening on port #{app.get('port')}"
