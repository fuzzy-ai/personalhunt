
express = require('express')
path = require('path')
favicon = require('static-favicon')
logger = require('morgan')
cookieParser = require('cookie-parser')
bodyParser = require('body-parser')
{Databank, DatabankObject} = require('databank')

routes = require('./index')

newApp = (config, callback) ->

  app = express()

  app.set 'port', config.port

  # view engine setup

  app.set 'views', path.join(__dirname, '..', 'views')
  app.set 'view engine', 'jade'
  app.use favicon()
  app.use logger('dev')
  app.use bodyParser.json()
  app.use bodyParser.urlencoded()
  app.use cookieParser()
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

  db = Databank.get config.driver, config.params

  db.connect {}, (err) ->
    if err
      callback err
    else
      app.db = db
      DatabankObject.bank = db
      callback null, app

module.exports = newApp
