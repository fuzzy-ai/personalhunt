qs = require 'querystring'
assert = require 'assert'

express = require 'express'
async = require 'async'
_ = require 'lodash'
web = require 'fuzzy.io-web'
moment = require 'moment-timezone'

User = require './user'
AccessToken = require './accesstoken'
UserAgent = require './useragent'
CacheItem = require './cacheitem'
ClientOnlyToken = require './clientonlytoken'

JSON_TYPE = "application/json"

router = express.Router()

THIRTY_MINUTES = 30 * 60 * 1000

cacheGet = (url, token, headers, callback) ->
  CacheItem.byUrlAndToken url, token, (err, cacheItem) ->
    if err
      callback err
    else
      if cacheItem && (Date.parse(cacheItem.updatedAt) > (Date.now() - THIRTY_MINUTES))
        callback null, cacheItem.body
      else
        if cacheItem
          headers["If-None-Match"] = cacheItem.etag
        web.get url, headers, (err, response, body) ->
          if err
            callback err
          else if response.statusCode == 304
            callback null, cacheItem.body
          else
            setImmediate ->
              if !cacheItem?
                cacheItem = new CacheItem({url: url, token: token})
              cacheItem.etag = response.headers.etag
              cacheItem.body = body
              cacheItem.save (err, saved) ->
                if err
                  console.error err
            callback null, body

ONE_DAY = 1000 * 60 * 60 * 24

getPostIDs = (token, day, callback) ->
  headers =
    "Accept": JSON_TYPE
    "Authorization": "Bearer #{token}"
  url = "https://api.producthunt.com/v1/posts?day=#{day}"
  cacheGet url, token, headers, (err, body) ->
    if err
      callback err
    else
      results = JSON.parse(body)
      ids = _.pluck results.posts, "id"
      callback null, ids

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
      high: [0, 1, 2]
    followingMakers:
      high: [0, 1, 2]
      veryHigh: [1, 2]
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
  for input, inputSets of agent.inputs
    weight = weights[input]
    for inputSet, inputShape of inputSets
      for output, outputSets of agent.outputs
        if _.has(outputSets, inputSet)
          rule = "IF #{input} IS #{inputSet} THEN #{output} IS #{inputSet} WITH #{weight}"
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

ONE_HOUR = 1000 * 60 * 60

# Gets a cached client-only token, or gets one from Product Hunt if needed

clientOnlyToken = (req, res, next) ->
  {clientID, clientSecret} = req.app.config
  ClientOnlyToken.get clientID, (err, cot) ->
    if err && err.name != "NoSuchThingError"
      next err
    else
      if cot && Date.parse(cot.expiresAt) > (Date.now() + ONE_HOUR)
        req.clientOnlyToken = cot.token
        next()
      else
        params =
          client_id: clientID
          client_secret: clientSecret
          grant_type: "client_credentials"

        payload = JSON.stringify params

        headers =
          "Accept": JSON_TYPE
          "Content-Type": JSON_TYPE
          "Content-Length": Buffer.byteLength payload

        url = 'https://api.producthunt.com/v1/oauth/token'

        web.post url, headers, payload, (err, response, body) ->
          if err
            next err
          else if response.statusCode != 200
            err = new Error("Bad status code #{response.statusCode} posting to #{url}: #{body}")
            next err
          else
            results = JSON.parse(body)
            if !cot?
              cot = new ClientOnlyToken({clientID: clientID})
            cot.token = results.access_token
            # XXX: expiration in seconds or milliseconds?
            cot.expiresAt = (new Date(Date.now() + (results.expires_in * 1000))).toISOString()
            cot.save (err) ->
              if err
                next err
              else
                req.clientOnlyToken = cot.token
                next()

router.get '/', (req, res, next) ->
  if !req.user?
    res.render 'index', title: 'Your Personal Product Hunt Leaderboard'
  else
    res.render 'home', title: "Products You May Have Missed"

router.get '/posts', userRequired, clientOnlyToken, (req, res, next) ->

  voters = (post) ->
    _.pluck(post.votes, "user_id")
  commenters = (post) ->
    commentersInArray = (comments) ->
      _.union(_.flatten(_.map(comments, commentersInComment)))
    commentersInComment = (comment) ->
      _.union [comment.user_id], commentersInArray(comment.child_comments)
    commentersInArray post.comments
  votedFor = (user, post) ->
    voters(post).indexOf(user.id) != -1
  commentedOn = (user, post) ->
    commenters(post).indexOf(user.id) != -1
  daysAgoToSFDay = (i) ->
    now = Date.now()
    ms = now - i * ONE_DAY
    moment(ms).tz('America/Los_Angeles').format('YYYY-MM-DD')

  days = _.map([0..6], daysAgoToSFDay)

  async.waterfall [
    (callback) ->
      async.parallel [
        (callback) ->
          req.app.db.read "UserFollowing", req.user.id, (err, following) ->
            if err and err.name == "NoSuchThingError"
              callback null, []
            else if err
              callback err
            else
              callback null, following
        (callback) ->
          downloadFullPost = (id, callback) ->
            token = req.clientOnlyToken
            headers =
              "Accept": JSON_TYPE
              "Authorization": "Bearer #{token}"
            url = "https://api.producthunt.com/v1/posts/#{id}"
            dfpstart = Date.now()
            cacheGet url, token, headers, (err, body) ->
              if err
                callback err
              else
                console.log "#{Date.now() - dfpstart} to get post with ID #{id}"
                results = JSON.parse(body)
                callback null, results.post
          getPostsForDay = (day, callback) ->
            async.waterfall [
              (callback) ->
                gpidsstart = Date.now()
                getPostIDs req.clientOnlyToken, day, (err, ids) ->
                  if err
                    callback err
                  else
                    console.log "#{Date.now() - gpidsstart} to get post ids for #{day}"
                    callback null, ids
              (ids, callback) ->
                mdfpstart = Date.now()
                async.map ids, downloadFullPost, (err, posts) ->
                  if err
                    callback err
                  else
                    console.log "#{Date.now() - mdfpstart} to download posts for #{day}"
                    posts = _.filter posts, (post) ->
                      !(votedFor(req.user, post) || commentedOn(req.user, post))
                    callback null, posts
            ], callback
          async.map days, getPostsForDay, (err, postses) ->
            if err
              callback err
            else
              posts = _.flatten postses
              callback null, posts
      ], callback
    (results, callback) ->
      [followings, posts] = results
      scorePosts = (posts, callback) ->
        inputses = []
        for post in posts
          inputs =
            relatedPostUpvotes: _.filter(post.related_posts, (related) -> votedFor(req.user, related)).length
            relatedPostComments: _.filter(post.related_posts, (related) -> commentedOn(req.user, related)).length
            followingHunters: _.filter([post.user], (user) -> followings.indexOf(user.id) != -1).length
            followingUpvotes: _.intersection(followings, voters(post)).length
            followingComments: _.intersection(followings, commenters(post)).length
            followingMakers: _.intersection(followings, _.pluck(post.makers, "id")).length
            totalUpvotes: post.votes_count
            totalComments: post.comments_count
          inputses.push inputs
        spstart = Date.now()
        req.app.fuzzyIO.evaluate req.agent, inputses, (err, outputses) ->
          if err
            console.error err
            callback err
          else
            console.log "#{Date.now() - spstart} to score #{posts.length} posts"
            for post, i in posts
              post.score = outputses[i].score
            callback null, posts
      scorePosts posts, callback
  ], (err, scored) ->
    if err
      next err
    else
      # Sort by descending score
      scored = _.sortByOrder scored, ["score"], [false]
      # Take only top 20
      scored = scored.slice 0, 20
      scored = _.map scored, (post) ->
        post.user.image_url = _.pick post.user.image_url, ["40px"]
        post.user = _.pick post.user, ["profile_url", "name", "image_url"]
        _.pick post, ["day", "score", "votes_count", "redirect_url", "discussion_url", "name", "tagline", "user", "comments_count"]
      res.json {days: days, posts: scored}

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

startedFlag = (req, res, next) ->
  req.startedFlag = true
  next()

showSettings = (req, res, next) ->
  firstTime = req.startedFlag
  getWeights req.app.fuzzyIO, req.agent, (err, weights) ->
    if err
      next err
    else
      adjusted = {}
      for input, weight of weights
        adjusted[input] = weight * 100
      res.render 'settings',
        title: if firstTime then 'Get Started' else 'Settings'
        firstTime: firstTime
        weights: adjusted

router.get '/getstarted', userRequired, startedFlag, showSettings
router.get '/settings', userRequired, showSettings

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
        callback new Error("Bad status code #{response.statusCode} getting #{url}: #{body}")
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

  firstTime = null

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
          err = new Error("Bad status code #{response.statusCode} posting to #{url}: #{body}")
          callback err
        else
          results = JSON.parse(body)
          token = results.access_token
          now = Date.now()
          console.log "#{now - start} (#{now - last}) to get token"
          last = now
          callback null
    (callback) ->
      url = 'https://api.producthunt.com/v1/me'
      web.get url, {Authorization: "Bearer #{token}"}, (err, response, body) ->
        if err
          callback err
        else if response.statusCode != 200
          callback new Error("Bad status code #{response.statusCode} getting #{url}: #{body}")
        else
          results = JSON.parse(body)
          user = results.user
          now = Date.now()
          console.log "#{now - start} (#{now - last}) to get user"
          last = now
          callback null
    (callback) ->
      User.get user.id, (err, got) ->
        if err and err.name = "NoSuchThingError"
          firstTime = true
          User.create user, callback
        else if err
          callback err
        else
          firstTime = false
          got.update user, (err, updated) ->
            if err
              callback err
            else
              callback null, updated
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
      else if firstTime
        returnTo = "/getstarted"
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
