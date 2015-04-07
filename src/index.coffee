qs = require 'querystring'

express = require 'express'
async = require 'async'

dummy = require "./dummy"
web = require './web'

JSON_TYPE = "application/json"

router = express.Router()

router.get '/', (req, res, next) ->
  if req.user
    token = req.app.config.devToken
    headers =
      "Accept": JSON_TYPE
      "Authorization": "Bearer #{token}"
    url = "https://api.producthunt.com/v1/posts"
    web.get url, headers, (err, response, body) ->
      if err
        next err
      else if response.statusCode != 200
        next new Error("Bad status code #{response.statusCode} getting posts: #{body}")
      else
        results = JSON.parse(body)
        res.render 'home',
          posts: results.posts
          title: "Today's Posts"
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
