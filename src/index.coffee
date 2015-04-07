qs = require 'querystring'

express = require 'express'
async = require 'async'

dummy = require "./dummy"
web = require './web'

JSON_TYPE = "application/json"

router = express.Router()

router.get '/', (req, res) ->
  if req.user
    res.render 'home',
      posts: dummy.posts.posts
      title: 'Home'
  else
    res.render 'index', title: 'Welcome'

router.get '/about', (req, res, next) ->
  res.render 'about', title: 'About'

router.get '/settings', (req, res, next) ->
  res.render 'settings', title: 'Settings'

router.post '/authorize', (req, res, next) ->
  app = req.app
  props =
    client_id: app.config.clientID
    redirect_uri: app.makeURL '/authorized'
    response_type: 'code'
    scope: 'public'
  url = 'https://api.producthunt.com/v1/oauth/authorize?' + qs.stringify(props)
  res.redirect url, 303

router.get '/authorized', (req, res, next) ->
  req.session.authorized = true
  res.redirect "/", 303

router.post '/logout', (req, res, next) ->
  req.session.authorized = false
  res.redirect "/", 303

module.exports = router
