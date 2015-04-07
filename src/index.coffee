qs = require 'querystring'

express = require 'express'
async = require 'async'

web = require './web'
User = require './user'
AccessToken = require './accesstoken'

JSON_TYPE = "application/json"

router = express.Router()

router.get '/', (req, res, next) ->
  if req.user
    token = req.token
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
    scope: 'public private'
  url = 'https://api.producthunt.com/v1/oauth/authorize?' + qs.stringify(props)
  res.redirect url, 303

router.get '/authorized', (req, res, next) ->

  code = req.query.code
  app = req.app

  token = null
  user = null

  async.waterfall [
    (callback) ->
      params =
        client_id: app.config.clientID
        client_secret: app.config.clientSecret
        redirect_uri: app.makeURL '/authorized'
        grant_type: 'authorization_code'
        code: code

      payload = JSON.stringify params

      headers =
        "Accept": JSON_TYPE
        "Content-Type": JSON_TYPE
        "Content-Length": Buffer.byteLength payload

      url = 'https://api.producthunt.com/v1/oauth/token'

      web.post url, headers, payload, (err, response, body) ->
        if err
          callback err
        else if response.statusCode != 200
          err = new Error("Bad status code #{response.statusCode}: #{body}")
          callback err
        else
          results = JSON.parse(body)
          token = results.access_token
          callback null
    (callback) ->
      web.get 'https://api.producthunt.com/v1/me', {Authorization: "Bearer #{token}"}, (err, response, body) ->
        if err
          callback err
        else if response.statusCode != 200
          callback new Error("Bad status code #{response.statusCode}: #{body}")
        else
          results = JSON.parse(body)
          user = results.user
          callback null
    (callback) ->
      User.ensure user, callback
    (ensured, callback) ->
      at = new AccessToken {token: token, user: user.id}
      at.save callback
  ], (err) ->
    if err
      next err
    else
      req.session.userID = user.id
      console.dir req.session
      res.redirect "/", 303

router.post '/logout', (req, res, next) ->
  delete req.session.userID
  res.redirect "/", 303

module.exports = router
