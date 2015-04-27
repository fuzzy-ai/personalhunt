qs = require 'querystring'
assert = require 'assert'

express = require 'express'
async = require 'async'
_ = require 'lodash'
LRU = require 'lru-cache'

web = require './web'
User = require './user'
AccessToken = require './accesstoken'
UserAgent = require './useragent'

JSON_TYPE = "application/json"

router = express.Router()

options =
  max: 128000000
  length: (n) -> return n.length
  maxAge: 1000 * 60 * 60 * 24 * 30

cache = LRU options

cacheGet = (url, token, headers, callback) ->
  key = "#{token}|#{url}"
  entry = null
  if cache.has(key)
    entry = JSON.parse(cache.get(key))
    if entry.etag
      headers["If-None-Match"] = entry.etag
  web.get url, headers, (err, response, body) ->
    if err
      callback err
    else if response.statusCode == 304
      callback null, entry.body
    else if response.statusCode != 200
      callback new Error("Bad status code #{response.statusCode} getting posts: #{body}")
    else
      key = "#{token}|#{url}"
      entry =
        url: url
        token: token
        etag: response.headers.etag
        body: body
      cache.set(key, JSON.stringify(entry))
      callback null, body

sortPosts = (db, client, agentID, posts, user, token, callback) ->
  assert.ok _.isObject(db), "#{db} is not an object"
  assert.ok _.isObject(client), "#{client} is not an object"
  assert.ok _.isString(agentID), "#{agentID} is not a string"
  assert.ok _.isArray(posts), "#{posts} is not an array"
  assert.ok _.isObject(user), "#{user} is not an object"
  assert.ok _.isString(token), "#{token} is not a string"

  async.waterfall [
    (callback) ->
      db.read "UserFollowing", user.id, (err, following) ->
        if err and err.name == "NoSuchThingError"
          callback null, []
        else if err
          callback err
        else
          callback null, following
    (followings, callback) ->
      scorePost = (post, callback) ->
        inputs =
          relatedPostUpvotes: _.filter(post.related_posts, (related) -> related?.current_user?.voted_for_post).length
          relatedPostComments: _.filter(post.related_posts, (related) -> related?.current_user?.commented_on_post).length
          followingHunters: _.filter([post.user], (user) -> followings.indexOf(user.id) != -1).length
          followingUpvotes: _.filter(post.votes, (vote) -> followings.indexOf(vote.user_id) != -1).length
          followingComments: 0
          totalUpvotes: post.votes_count
          totalComments: post.comments_count
        client.evaluate agentID, inputs, (err, outputs) ->
          if err
            callback err
          else
            post.score = outputs.score
            callback null, post
      async.mapLimit posts, 4, scorePost, (err, scored) ->
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

defaultWeights = {}

for input, value of defaultAgent.inputs
  defaultWeights[input] = 0.5

makeAgent = (weights) ->
  agent = _.cloneDeep(defaultAgent)
  for input, value of agent.inputs
    weight = weights[input]
    for output, value of agent.outputs
      for set in ['veryLow', 'low', 'medium', 'high', 'veryHigh']
        rule = "IF #{input} IS #{set} THEN #{output} is #{set} WITH #{weight}"
        agent.rules.push rule
  agent

makeDefaultUserAgent = (client, user, callback) ->
  agent = makeAgent defaultWeights
  async.waterfall [
    (callback) ->
      client.newAgent agent, callback
    (agent, callback) ->
      UserAgent.create {user: user, agent: agent.id}, callback
  ], callback

updateUserAgent = (client, user, agentID, weights, callback) ->

  assert.ok _.isObject(client), "#{client} is not an object"
  assert.ok _.isObject(user), "#{user} is not an object"
  assert.ok _.isString(agentID), "#{agentID} is not a string"
  assert.ok _.isObject(weights), "#{weights} is not an object"

  newAgent = makeAgent weights
  client.putAgent agentID, newAgent, callback

userRequired = (req, res, next) ->
  if req.user?
    next()
  else
    req.session.returnTo = req.url
    res.redirect '/', 303

router.get '/', (req, res, next) ->
  if !req.user?
    res.render 'index', title: 'Your Personal Product Hunt Leaderboard'
  else
    res.render 'home', title: "Today's Posts"

router.get '/posts', userRequired, (req, res, next) ->
    start = last = Date.now()
    async.waterfall [
      (callback) ->
        token = req.token
        headers =
          "Accept": JSON_TYPE
          "Authorization": "Bearer #{token}"
        url = "https://api.producthunt.com/v1/posts"
        cacheGet url, token, headers, (err, body) ->
          if err
            callback err
          else
            results = JSON.parse(body)
            now = Date.now()
            console.log "#{now - start} (#{now - last}) to get posts"
            last = now
            callback null, results.posts
      (posts, callback) ->
        downloadFullPost = (post, callback) ->
          token = req.token
          headers =
            "Accept": JSON_TYPE
            "Authorization": "Bearer #{token}"
          url = "https://api.producthunt.com/v1/posts/#{post.id}"
          cacheGet url, token, headers, (err, body) ->
            if err
              callback err
            else
              results = JSON.parse(body)
              callback null, results.post
        async.map posts, downloadFullPost, callback
      (posts, callback) ->
        now = Date.now()
        console.log "#{now - start} (#{now - last}) to get full posts"
        last = now
        sortPosts req.app.db, req.app.fuzzyIO, req.agent, posts, req.user, req.token, callback
    ], (err, posts) ->
      if err
        next err
      else
        now = Date.now()
        console.log "#{now - start} (#{now - last}) to sort posts"
        last = now
        res.json posts

router.get '/about', (req, res, next) ->
  res.render 'about', title: 'About'

getWeights = (client, agentID, callback) ->
  client.getAgent agentID, (err, agent) ->
    if err
      callback err
    else
      weights = {}
      # defaults
      for input, value of agent.inputs
        weights[input] = 0.5
      # read from rules
      for rule in agent.rules
        match = rule.match /^IF (\S+) IS .*? WITH ([\d\.]+)$/
        if match
          [all, input, weight] = match
          weights[input] = parseFloat(weight)
      callback null, weights

router.get '/settings', userRequired, (req, res, next) ->
  getWeights req.app.fuzzyIO, req.agent, (err, weights) ->
    if err
      callback err
    else
      adjusted = {}
      for input, weight of weights
        adjusted[input] = weight * 100
      res.render 'settings', {title: 'Settings', weights: adjusted}

camelCase = (name) ->
  parts = name.split '-'
  parts[0] + _.map(parts.slice(1), (str) -> str.charAt(0).toUpperCase() + str.slice(1)).join('')

router.post '/settings', (req, res, next) ->
  weights = {}
  for name, value of req.body
    weights[camelCase(name)] = parseInt(value, 10)/100
  updateUserAgent req.app.fuzzyIO, req.user, req.agent, weights, (err) ->
    if err
      next err
    else
      res.json({message: "OK"})

router.post '/authorize', (req, res, next) ->
  app = req.app
  props =
    client_id: app.config.clientID
    redirect_uri: app.makeURL '/authorized'
    response_type: 'code'
    scope: 'public private'
  url = 'https://api.producthunt.com/v1/oauth/authorize?' + qs.stringify(props)
  res.redirect url, 303

updateFollowing = (db, user, token, callback) ->

  following = []

  getNext = (oldest, callback) ->

    params =
      per_page: 100
      order: "desc"

    if oldest?
      params.older = oldest

    url = "https://api.producthunt.com/v1/users/#{user.id}/following?" + qs.stringify(params)

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
      db.save "UserFollowing", user.id, following, callback

router.get '/authorized', (req, res, next) ->

  code = req.query.code
  app = req.app

  token = null
  user = null

  last = start = Date.now()

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
          now = Date.now()
          console.log "#{now - start} (#{now - last}) to get token"
          last = now
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
          now = Date.now()
          console.log "#{now - start} (#{now - last}) to get user"
          last = now
          callback null
    (callback) ->
      User.ensure user, callback
    (ensured, callback) ->
      now = Date.now()
      console.log "#{now - start} (#{now - last}) to get ensured"
      last = now
      at = new AccessToken {token: token, user: user.id}
      at.save callback
    (saved, callback) ->
      now = Date.now()
      console.log "#{now - start} (#{now - last}) to save access token"
      last = now
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

      now = Date.now()
      console.log "#{now - start} (#{now - last}) to get user token"
      last = now

      req.session.userID = user.id

      setImmediate ->
        updateFollowing req.app.db, user, token, (err, following) ->
          if err
            console.error err
          else
            console.log "Updated following for #{user.id}: #{following.length}"

      if req.session.returnTo
        returnTo = req.session.returnTo
        delete req.session.returnTo
      else
        returnTo = "/"

      res.redirect returnTo, 303

router.post '/logout', (req, res, next) ->
  if req.user
    delete req.session.userID
    req.user = null
    req.token = null
    req.agent = null
  res.redirect "/", 303

module.exports = router
