newApp = require('./app')

config =
  port: if process.env.PORT then parseInt(process.env.PORT, 10) else 80
  key: process.env.KEY
  cert: process.env.CERT
  hostname: process.env.HOSTNAME
  address: process.env.ADDRESS or '0.0.0.0'
  driver: process.env.DRIVER or "mongodb"
  params: if process.env.PARAMS then JSON.parse(process.env.PARAMS) else {}
  clientID: process.env.CLIENT_ID
  clientSecret: process.env.CLIENT_SECRET
  secret: process.env.SECRET or "bad secret"
  devToken: process.env.DEV_TOKEN
  fuzzyIOAPIKey: process.env.FUZZY_IO_API_KEY
  logLevel: process.env.LOG_LEVEL or "info"
  logFile: process.env.LOG_FILE or null
  redisHost: process.env.REDIS_HOST or "localhost"
  redisPort: process.env.REDIS_PORT or 6379
  urlPrefix: process.env.URL_PREFIX or null

console.log "Creating app..."

newApp config, (err, app) ->
  if err
    console.error err
    process.exit -1
  else
    console.log "App created. Starting..."
    app.start (err) ->
      if err
        console.error err
        process.exit -1
      else
        console.log "Express server listening on port #{app.get('port')}"
