http = require 'http'
https = require 'https'
path = require 'path'
urlFormat = require('url').format

express = require 'express'
session = require 'express-session'
favicon = require 'static-favicon'
logger = require 'morgan'
cookieParser = require 'cookie-parser'
bodyParser = require 'body-parser'
{Databank, DatabankObject} = require('databank')
async = require 'async'
_ = require 'lodash'

routes = require './index'
AccessToken = require './accesstoken'
User = require './user'
Post = require './post'

newApp = (config, callback) ->

  app = express()

  app.config = config

  app.makeURL = (relative, search) ->

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

  app.set 'port', config.port

  # view engine setup

  app.set 'views', path.join(__dirname, '..', 'views')
  app.set 'view engine', 'jade'
  app.use favicon()
  app.use logger('dev')
  app.use bodyParser.json()
  app.use bodyParser.urlencoded()
  app.use cookieParser()
  app.use session {secret: config.secret}
  app.use express.static(path.join(__dirname, '..', 'public'))

  app.use '/', routes

  #/ catch 404 and forwarding to error handler

  app.use (req, res, next) ->
    err = new Error('Not Found')
    err.status = 404
    next err
    return

  #/ error handlers
  # development error handler
  # will print stacktrace

  app.use (err, req, res, next) ->
    res.status err.status or 500
    res.render 'error',
      message: err.message
      error: err
    return

  config.params.schema =
    User: User.schema
    Post: Post.schema
    AccessToken: AccessToken.schema

  app.start = (callback) ->
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
