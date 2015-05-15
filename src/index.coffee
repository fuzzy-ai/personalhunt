qs = require 'querystring'

express = require 'express'
async = require 'async'
_ = require 'lodash'
web = require 'fuzzy.io-web'

User = require './user'
AccessToken = require './accesstoken'
UserAgent = require './useragent'
ClientOnlyToken = require './clientonlytoken'
SavedScore = require './savedscore'
recentPosts = require './recentposts'
agent = require './agent'

JSON_TYPE = "application/json"

router = express.Router()

userRequired = (req, res, next) ->
  if req.user?
    next()
  else
    req.session.returnTo = req.url
    res.redirect '/', 303

# Gets a cached client-only token, or gets one from Product Hunt if needed

clientOnlyToken = (req, res, next) ->
  {clientID, clientSecret} = req.app.config
  ClientOnlyToken.ensure clientID, clientSecret, (err, token) ->
    if err
      next err
    else
      req.clientOnlyToken = token
      next()

router.get '/', (req, res, next) ->
  if !req.user?
    res.render 'index', title: 'Your Personal Product Hunt Leaderboard'
  else
    res.render 'home', title: "Recent Hunts You Might Like (And May Have Missed)"

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

  days = null

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
          recentPosts.get req.clientOnlyToken, callback
      ], callback
    (results, callback) ->
      [followings, others] = results
      [posts, days] = others
      # Filter ones you voted for or commented on
      posts = _.filter posts, (post) ->
        !(votedFor(req.user, post) || commentedOn(req.user, post))
      getSavedScores = (inputses, version, callback) ->
        idMap = {}
        for postID, inputs of inputses
          key = SavedScore.makeKey postID, inputs, version
          idMap[key] = postID
        SavedScore.readAll _.keys(idMap), (err, savedScores) ->
          if err
            callback err
          else
            scoreMap = {}
            for key, savedScore of savedScores
              scoreMap[idMap[key]] = savedScore?.outputs?.score
            callback null, scoreMap
      scorePosts = (posts, callback) ->
        inputses = {}
        postMap = {}
        toScore = {}
        for post in posts
          postMap[post.id] = post
          if (post.user? && followings.indexOf(post.user.id) != -1)
            fh = 1
          else
            fh = 0
          inputses[post.id] =
            relatedPostUpvotes: _.filter(post.related_posts, (related) -> votedFor(req.user, related)).length
            relatedPostComments: _.filter(post.related_posts, (related) -> commentedOn(req.user, related)).length
            followingHunters: fh
            followingUpvotes: _.intersection(followings, voters(post)).length
            followingComments: _.intersection(followings, commenters(post)).length
            followingMakers: _.intersection(followings, _.pluck(post.makers, "id")).length
            totalUpvotes: post.votes_count
            totalComments: post.comments_count
        spstart = Date.now()
        console.log "Getting saved scores..."
        getSavedScores inputses, req.agentVersion, (err, scoreMap) ->
          if err
            return callback err
          scored = unscored = 0
          for postID, score of scoreMap
            if score
              scored++
              postMap[postID].score = score
            else
              unscored++
              toScore[postID] = inputses[postID]
          ids = _.keys toScore
          ids.sort()
          scoreInputs = ids.map (ids) -> toScore[ids]
          if ids.length == 0
            console.log "No unscored posts."
            callback null, posts
          else
            console.log "Making request to fuzzy.io"
            req.app.fuzzyIO.evaluate req.agent, scoreInputs, (err, outputses) ->
              if err
                console.error err
                callback err
              else
                console.log "Done with request to fuzzy.io"
                outputsMap = {}
                for outputs, i in outputses
                  outputsMap[ids[i]] = outputs
                  postMap[ids[i]].score = outputs.score
                saveScore = (id, callback) ->
                  props =
                    postID: id
                    version: req.agentVersion
                    inputs: inputses[id]
                    outputs: outputsMap[id]
                  SavedScore.create props, (err) ->
                    if err && err.name != "AlreadyExistsError"
                      callback err
                    else
                      callback null
                console.log "Saving scores."
                async.each ids, saveScore, (err) ->
                  if err
                    callback err
                  else
                    console.log "#{Date.now() - spstart} to score #{ids.length} posts out of #{posts.length} total"
                    # Don't return unscored posts
                    posts = _.filter posts, (post) -> post?.score?
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
      console.dir _.keys(scored[0])
      scored = _.map scored, (post) ->
        post.user.image_url = _.pick post.user.image_url, ["40px"]
        post.user = _.pick post.user, ["profile_url", "name", "image_url"]
        _.pick post, ["id", "day", "score", "votes_count", "redirect_url", "discussion_url", "name", "tagline", "user", "comments_count"]
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

showSettings = (req, res, next) ->
  getWeights req.app.fuzzyIO, req.agent, (err, weights) ->
    if err
      next err
    else
      adjusted = {}
      for input, weight of weights
        adjusted[input] = weight * 100
      res.render 'settings',
        title: 'Settings'
        weights: adjusted

router.get '/settings', userRequired, showSettings

camelCase = (name) ->
  parts = name.split '-'
  parts[0] + _.map(parts.slice(1), (str) -> str.charAt(0).toUpperCase() + str.slice(1)).join('')

router.post '/settings', (req, res, next) ->
  weights = {}
  for name, value of req.body
    weights[camelCase(name)] = parseInt(value, 10)/100
  agent.update req.app.fuzzyIO, req.user, req.agent, weights, (err) ->
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
      at = new AccessToken {token: token, user: user.id}
      at.save callback
    (saved, callback) ->
      UserAgent.get user.id, (err, inst) ->
        if err
          if err.name == "NoSuchThingError"
            agent.makeDefault req.app.fuzzyIO, user.id, callback
          else
            callback err
        else
          callback null, inst
  ], (err) ->
    if err
      next err
    else

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
    req.agentVersion = null
  res.redirect "/", 303

module.exports = router
