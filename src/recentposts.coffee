# getrecentposts.coffee

qs = require 'querystring'

async = require 'async'
_ = require 'lodash'
moment = require 'moment-timezone'
web = require 'fuzzy.io-web'

CacheItem = require './cacheitem'

THIRTY_MINUTES = 30 * 60 * 1000
ONE_DAY = 24 * 60 * 60 * 1000

JSON_TYPE = "application/json"

cacheGet = (url, token, headers, cacheMax, callback) ->
  if !callback?
    callback = cacheMax
    cacheMax = THIRTY_MINUTES
  CacheItem.byUrlAndToken url, token, (err, cacheItem) ->
    if err
      callback err
    else
      if cacheItem && (Date.parse(cacheItem.updatedAt) > (Date.now() - cacheMax))
        callback null, cacheItem.body
      else
        if cacheItem
          headers["If-None-Match"] = cacheItem.etag
        web.get url, headers, (err, response, body) ->
          if err
            callback err
          else if response.statusCode == 304
            # Touch the cache item for another 30 minutes
            setImmediate ->
              cacheItem.save (err) ->
                if err
                  console.error err
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

daysAgoToSFDay = (i) ->
  now = Date.now()
  ms = now - i * ONE_DAY
  moment(ms).tz('America/Los_Angeles').format('YYYY-MM-DD')

getCached = (callback) ->

  # XXX: stinks

  db = CacheItem.bank()

  db.read "RecentPosts", 0, (err, recentPosts) ->
    if err && err.name == "NoSuchThingError"
      callback null, null
    else if err
      callback err, null
    else
      callback null, recentPosts

saveCached = (recentPosts, callback) ->

  # XXX: stinks

  db = CacheItem.bank()

  db.save "RecentPosts", 0, recentPosts, (err, recentPosts) ->
    if err
      callback err
    else
      callback null

updateRecentPosts = (token, callback) ->

  getAllComments = (post, cacheMax, callback) ->

    comments = []

    getNextComments = (oldest, callback) ->

      params =
        per_page: 50
        order: "desc"

      if oldest?
        params.older = oldest

      headers =
        "Accept": JSON_TYPE
        "Authorization": "Bearer #{token}"

      url = "https://api.producthunt.com/v1/posts/#{post.id}/comments?" + qs.stringify(params)

      cacheGet url, token, headers, cacheMax, (err, body) ->
        if err
          callback err
        else
          results = JSON.parse(body)
          if results.comments?.length > 0
            comments = comments.concat results.comments
            if comments.length < post.comments_count
              oldest = comments[comments.length - 1].id
              getNextComments oldest, callback
            else
              callback null, comments
          else
            callback null, comments

    getNextComments null, (err, comments) ->
      if err
        callback err
      else
        post.comments = comments
        callback null

  getAllVotes = (post, cacheMax, callback) ->

    votes = []

    getNextVotes = (oldest, callback) ->

      params =
        per_page: 50
        order: "desc"

      if oldest?
        params.older = oldest

      headers =
        "Accept": JSON_TYPE
        "Authorization": "Bearer #{token}"

      url = "https://api.producthunt.com/v1/posts/#{post.id}/votes?" + qs.stringify(params)

      cacheGet url, token, headers, cacheMax, (err, body) ->
        if err
          callback err
        else
          results = JSON.parse(body)
          if results.votes?.length > 0
            votes = votes.concat results.votes
            if votes.length < post.votes_count
              oldest = votes[votes.length - 1].id
              getNextVotes oldest, callback
            else
              callback null, votes
          else
            callback null, votes

    getNextVotes null, (err, votes) ->
      if err
        callback err
      else
        post.votes = votes
        callback null

  getPostsForDay = (day, callback) ->

    posts = null

    if day == daysAgoToSFDay 0
      cacheMax = THIRTY_MINUTES
    else
      cacheMax = ONE_DAY

    async.waterfall [
      (callback) ->
        headers =
          "Accept": JSON_TYPE
          "Authorization": "Bearer #{token}"
        url = "https://api.producthunt.com/v1/posts?day=#{day}"
        cacheGet url, token, headers, cacheMax, (err, body) ->
          if err
            callback err
          else
            results = JSON.parse(body)
            posts = results.posts
            callback null
      (callback) ->
        gac = (post, callback) ->
          getAllComments post, cacheMax, callback
        gav = (post, callback) ->
          getAllVotes post, cacheMax, callback
        async.parallel [
          (callback) ->
            async.each posts, gac, (err, posts) ->
              if err
                callback err
              else
                callback null
          (callback) ->
            async.each posts, gav, (err) ->
              if err
                callback err
              else
                callback null
        ], callback
    ], (err) ->
      if err
        callback err
      else
        callback null, posts

  days = _.map([0..6], daysAgoToSFDay)

  gpfdmstart = Date.now()

  async.map days, getPostsForDay, (err, postses) ->
    if err
      callback err
    else
      posts = _.flatten postses
      console.log "#{Date.now() - gpfdmstart} to retrieve #{posts.length} posts"
      posts = _.map posts, (post) ->
        post.user.image_url = _.pick post.user.image_url, ["40px"]
        post.user = _.pick post.user, ["profile_url", "name", "image_url"]
        post.votes = _.map post.votes, (vote) ->
          _.pick vote, ["user_id"]
        scrubComment = (comment) ->
          comment.child_comments = _.map comment.child_comments, scrubComment
          _.pick comment, ["user_id", "child_comments"]
        post.comments = _.map post.comments, scrubComment
        _.pick post, ["id", "day", "votes", "comments", "votes_count", "redirect_url", "discussion_url", "name", "tagline", "user", "comments_count", "related_posts"]
      saveCached posts, (err) ->
        if err
          callback err
        else
          callback null, posts, days

getRecentPosts = (token, callback) ->
  getCached (err, recentPosts) ->
    if err
      callback err
    else if recentPosts?
      days = _.map([0..6], daysAgoToSFDay)
      callback null, recentPosts, days
    else
      updateRecentPosts token, (err, posts, days) ->
        if err
          callback err
        else
          callback null, posts, days

module.exports =
  get: getRecentPosts
  update: updateRecentPosts
