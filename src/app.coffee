http = require 'http'
https = require 'https'
path = require 'path'
urlFormat = require('url').format

express = require 'express'
session = require 'express-session'
RedisStore = require('connect-redis')(session)
favicon = require 'static-favicon'
cookieParser = require 'cookie-parser'
bodyParser = require 'body-parser'
{Databank, DatabankObject} = require('databank')
async = require 'async'
_ = require 'lodash'
FuzzyIOClient = require 'fuzzy.io'
Logger = require 'bunyan'
uuid = require 'node-uuid'
web = require 'fuzzy.io-web'

routes = require './index'
AccessToken = require './accesstoken'
User = require './user'
Post = require './post'
UserAgent = require './useragent'
CacheItem = require './cacheitem'
ClientOnlyToken = require './clientonlytoken'
SavedScore = require './savedscore'
recentPosts = require './recentposts'

newApp = (config, callback) ->

  app = express()

  app.config = config

  app.makeURL = (relative, search) ->

    if @config.urlPrefix
      "#{@config.urlPrefix}#{relative}"
    else
      props =
        protocol: if @config.key then 'https' else 'http'
        hostname: @config.hostname
        pathname: relative

      if @config.key?
        if @config.port != 443
          props.port = @config.port
      else
        if @config.port != 80
          props.port = @config.port

      if search
        props.search = search

      urlFormat props

  setupLogger = (cfg) ->
    logParams =
      serializers:
        req: Logger.stdSerializers.req
        res: Logger.stdSerializers.res
        err: Logger.stdSerializers.err
      level: cfg.logLevel

    if cfg.logFile
        logParams.streams = [{path: cfg.logFile}]
    else
        logParams.streams = [{stream: process.stdout}]

    logParams.name = "personalhunt"

    log = new Logger logParams

    log.debug "Initializing"

    log

  requestLogger = (req, res, next) ->
    start = Date.now()
    req.id = uuid.v4()
    weblog = req.app.log.child({"req_id": req.id, "url": req.originalUrl, method: req.method, component: "web"})
    end = res.end
    req.log = weblog
    res.end = (chunk, encoding) ->
      res.end = end
      res.end(chunk, encoding)
      token = req.token
      # Obfuscate the token
      if token
        token = token.slice(0, 4) + "..." + token.slice(-4)
      rec = {elapsed: Date.now() - start, req: req, res: res, user: req.user?.username, token: token, agent: req.agent}
      weblog.info(rec, "Completed request.")
    next()

  app.fuzzyIO = new FuzzyIOClient config.fuzzyIOAPIKey

  app.set 'port', config.port

  app.log = setupLogger config

  # view engine setup

  app.set 'views', path.join(__dirname, '..', 'views')
  app.set 'view engine', 'jade'
  app.use requestLogger
  app.use favicon(path.join(__dirname, '..', 'public', 'images', 'favicon.ico'))
  app.use bodyParser.json()
  app.use bodyParser.urlencoded()
  app.use cookieParser()
  app.use session {store: new RedisStore({host: config.redisHost, port: config.redisPort}), secret: config.secret}
  app.use (req, res, next) ->
    if req.session.userID
      async.parallel [
        (callback) ->
          User.get req.session.userID, callback
        (callback) ->
          AccessToken.get req.session.userID, callback
        (callback) ->
          UserAgent.get req.session.userID, callback
      ], (err, results) ->
        if err
          console.error err
          # Soft failure; just log them out
          delete req.session.userID
          req.user = null
          req.token = null
          req.agent = null
          req.agentVersion = null
          next()
        else
          [user, accessToken, userAgent] = results
          req.user = res.locals.user = user
          req.token = accessToken.token
          req.agent = userAgent.agent
          req.agentVersion = userAgent.version
          next()
    else
      req.user = res.locals.user = null
      req.token = null
      next()
  app.use express.static(path.join(__dirname, '..', 'public'))
  app.use express.static(path.join(__dirname, "..", "node_modules", "bootstrap-slider", "dist"))

  app.use '/', routes

  #/ catch 404 and forwarding to error handler

  app.use (req, res, next) ->
    err = new Error('Not Found')
    err.statusCode = 404
    return next err

  # Error handler

  app.use (err, req, res, next) ->
    if err.statusCode
      res.statusCode = err.statusCode
    else if err.name == "NoSuchThingError"
      res.statusCode = 404
    else
      res.statusCode = 500
    log = if req.log then req.log else req.app.log
    log.error {err: err}, "Error"
    res.render 'error', {err: err, title: "Error"}

  config.params.schema =
    User: User.schema
    Post: Post.schema
    AccessToken: AccessToken.schema
    UserAgent: UserAgent.schema
    CacheItem: CacheItem.schema
    ClientOnlyToken: ClientOnlyToken.schema
    SavedScore: SavedScore.schema

  app.start = (callback) ->
    # Initialize agents
    FuzzyIOClient.start()
    web.start()
    async.waterfall [
      (callback) =>
        console.log "Connecting to databank..."
        db = Databank.get config.driver, config.params
        db.connect {}, (err) =>
          if err
            console.error err
            callback err
          else
            @db = db
            DatabankObject.bank = db
            console.log "Connected."
            callback null
      (callback) =>
        warmUpCache = (callback) ->
          console.log "Warming up recent posts cache..."
          async.waterfall [
            (callback) ->
              ClientOnlyToken.ensure config.clientID, config.clientSecret, callback
            (token, callback) ->
              recentPosts.update token, callback
          ], callback
        periodic = () ->
          warmUpCache (err, posts, days) ->
            if err
              console.error err
            else
              console.dir {posts: posts.length, days: days, message: "Warmed up cache"}
        # Warm up every 30 minutes
        startPeriodic = () ->
          @warmupInterval = setInterval periodic, 30 * 60 * 1000
        # Use a random offset so load-balanced servers warm up at different times
        setTimeout startPeriodic, Math.floor(Math.random() * 30 * 60 * 1000)
        # Warm up now
        warmUpCache (err) ->
          callback err
      (callback) =>
        console.log "Starting HTTP server..."
        if @config.key
          options =
            key: @config.key
            cert: @config.cert
          server = https.createServer options, app
        else
          server = http.createServer app
        server.once 'error', (err) =>
          callback err
        server.once 'listening', =>
          callback null
        server.listen @get('port'), @config.address
    ], (err) =>
      callback err

  callback null, app

module.exports = newApp
