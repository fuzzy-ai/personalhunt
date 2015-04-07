qs = require 'querystring'

express = require 'express'
async = require 'async'
_ = require 'lodash'

web = require './web'
User = require './user'
AccessToken = require './accesstoken'
UserAgent = require './useragent'

JSON_TYPE = "application/json"

router = express.Router()

sortPosts = (db, client, agentID, posts, user, token, callback) ->
  async.waterfall [
    (callback) ->
      db.read "UserFollowing", user.id, callback
    (followings, callback) ->
      scorePost = (post, callback) ->
        console.dir {id: post.id, related: post.related_posts}
        inputs =
          relatedPostUpvotes: 0
          relatedPostComments: 0
          followingHunters: _.filter([post.user], (user) -> followings.indexOf(user.id) != -1).length
          followingUpvotes: _.filter(post.votes, (vote) -> followings.indexOf(vote.user_id) != -1).length
          followingComments: 0
          totalUpvotes: post.votes_count
          totalComments: post.comments_count
        client.evaluate agentID, inputs, (err, outputs) ->
          if err
            console.error err
            callback err
          else
            post.score = outputs.score
            callback null, post
      async.map posts, scorePost, (err, scored) ->
        if err
          callback err
        else
          scored = _.sortByOrder scored, ["score"], [false]
          callback null, scored
  ], callback

defaultAgent =
  inputs:
    relatedPostUpvotes:
      veryLow: [0, 1]
      low: [0, 1, 2]
      medium: [1, 2, 3]
      high: [2, 3, 4]
      veryHigh: [3, 4]
    relatedPostComments:
      veryLow: [0, 1]
      low: [0, 1, 2]
      medium: [1, 2, 3]
      high: [2, 3, 4]
      veryHigh: [3, 4]
    followingHunters:
      veryLow: [0, 1]
      low: [0, 1, 2]
      medium: [1, 2, 3]
      high: [2, 3, 4]
      veryHigh: [3, 4]
    followingUpvotes:
      veryLow: [0, 12.5]
      low: [0, 12.5, 25]
      medium: [12.5, 25, 37.5]
      high: [25, 37.5, 50]
      veryHigh: [37.5, 50]
    followingComments:
      veryLow: [0, 1]
      low: [0, 1, 2]
      medium: [1, 2, 3]
      high: [2, 3, 4]
      veryHigh: [3, 4]
    totalUpvotes:
      veryLow: [0, 125]
      low: [0, 125, 250]
      medium: [125, 250, 375]
      high: [250, 375, 500]
      veryHigh: [375, 500]
    totalComments:
      veryLow: [0, 10]
      low: [0, 10, 20]
      medium: [10, 20, 30]
      high: [20, 30, 40]
      veryHigh: [30, 40]
  outputs:
    score:
      veryLow: [0, 25]
      low: [0, 25, 50]
      medium: [25, 50, 75]
      high: [50, 75, 100]
      veryHigh: [75, 100]
  rules: []

for input, value of defaultAgent.inputs
  for output, value of defaultAgent.outputs
    for set in ['veryLow', 'low', 'medium', 'high', 'veryHigh']
      rule = "IF #{input} IS #{set} THEN #{output} is #{set}"
      defaultAgent.rules.push rule

makeDefaultUserAgent = (client, user, callback) ->
  async.waterfall [
    (callback) ->
      client.newAgent defaultAgent, callback
    (agent, callback) ->
      UserAgent.create {user: user, agent: agent.id}, callback
  ], callback

router.get '/', (req, res, next) ->
  if !req.user?
    res.render 'index', title: 'Welcome'
  else
    async.waterfall [
      (callback) ->
        token = req.token
        headers =
          "Accept": JSON_TYPE
          "Authorization": "Bearer #{token}"
        url = "https://api.producthunt.com/v1/posts"
        web.get url, headers, (err, response, body) ->
          if err
            callback err
          else if response.statusCode != 200
            callback new Error("Bad status code #{response.statusCode} getting posts: #{body}")
          else
            results = JSON.parse(body)
            callback null, results.posts
      (posts, callback) ->
        downloadFullPost = (post, callback) ->
          token = req.token
          headers =
            "Accept": JSON_TYPE
            "Authorization": "Bearer #{token}"
          url = "https://api.producthunt.com/v1/posts/#{post.id}"
          web.get url, headers, (err, response, body) ->
            if err
              callback err
            else if response.statusCode != 200
              callback new Error("Bad status code #{response.statusCode} getting posts: #{body}")
            else
              results = JSON.parse(body)
              callback null, results.post
        async.map posts, downloadFullPost, callback
      (posts, callback) ->
        sortPosts req.app.db, req.app.fuzzyIO, req.agent, posts, req.user, req.token, callback
    ], (err, posts) ->
      if err
        next err
      else
        res.render 'home',
          posts: posts
          title: "Today's Posts"

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
      following = []
      getNext = (oldest, callback) ->

        params =
          per_page: 100
          order: "desc"

        if oldest?
          params.older = oldest

        url = "https://api.producthunt.com/v1/users/#{user.id}/following?" + qs.stringify(params)

        console.dir url

        web.get url, {Authorization: "Bearer #{token}"}, (err, response, body) ->
          if err
            callback err
          else if response.statusCode != 200
            callback new Error("Bad status code #{response.statusCode}: #{body}")
          else
            results = JSON.parse(body)
            page = _.pluck results.following, "id"
            users = _.pluck results.following, "user"
            userIDs = _.map(_.pluck(users, "id"), (id) -> parseInt(id, 10))
            if page.length > 0
              following = following.concat userIDs
              getNext page[page.length - 1], callback
            else
              callback null, _.uniq(following.sort())
      getNext null, (err, following) ->
        if err
          callback err
        else
          req.app.db.save "UserFollowing", user.id, following, callback
    (following, callback) ->
      at = new AccessToken {token: token, user: user.id}
      at.save callback
    (saved, callback) ->
      UserAgent.get user.id, (err, agent) ->
        if err
          if err.name == "NoSuchThingError"
            makeDefaultUserAgent req.app.fuzzyIO, user.id, callback
          else
            callback err
        else
          callback null, agent
  ], (err) ->
    if err
      next err
    else
      req.session.userID = user.id
      res.redirect "/", 303

router.post '/logout', (req, res, next) ->
  delete req.session.userID
  res.redirect "/", 303

module.exports = router
