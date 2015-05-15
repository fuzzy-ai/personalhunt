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

getRecentPosts = (token, callback) ->

  getAllComments = (post, callback) ->

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

      cacheGet url, token, headers, (err, body) ->
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

  getAllVotes = (post, callback) ->

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

      cacheGet url, token, headers, (err, body) ->
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

    async.waterfall [
      (callback) ->
        headers =
          "Accept": JSON_TYPE
          "Authorization": "Bearer #{token}"
        url = "https://api.producthunt.com/v1/posts?day=#{day}"
        cacheGet url, token, headers, (err, body) ->
          if err
            callback err
          else
            results = JSON.parse(body)
            posts = results.posts
            callback null
      (callback) ->
        async.parallel [
          (callback) ->
            async.each posts, getAllComments, (err, posts) ->
              if err
                callback err
              else
                callback null
          (callback) ->
            async.each posts, getAllVotes, (err) ->
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
      _.each posts, (post) ->
        if post?.votes?.length != post.votes_count
          console.dir {votesLength: post?.votes?.length, voteCount: post.votes_count, post: post.id, "Vote counts don't match up"}
      callback null, posts, days

module.exports = getRecentPosts
