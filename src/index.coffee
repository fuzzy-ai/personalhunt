qs = require 'querystring'

express = require 'express'
async = require 'async'

dummy = require "./dummy"
web = require './web'

router = express.Router()

router.get '/', (req, res) ->
  res.render 'index', title: 'Welcome'
  return

router.get '/home', (req, res, next) ->
  res.render 'home',
    posts: dummy.posts.posts
    title: 'Home'

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

      headers =
        "Accept": "application/json"
        "Content-Type": "application/json"

      url = 'https://api.producthunt.com/v1/oauth/token'

      web.post url, headers, JSON.stringify(params), (err, response, body) ->
        if err
          callback err
        else if response.statusCode != 200
          callback new Error("Bad status code #{response.statusCode}: #{body}")
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
          user = JSON.parse(body)
          callback null
    (callback) ->
      User.ensure user, callback
    (ensured, callback) ->
      AccessToken.create {token: token, user: user.id}, callback
  ], (err) ->
    if err
      next err
    else
      req.session.user = user.id
      res.redirect "/home", 303

module.exports = router
