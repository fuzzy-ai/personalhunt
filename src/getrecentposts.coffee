# getrecentposts.coffee

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

getRecentPosts = (clientOnlyToken, callback) ->

    daysAgoToSFDay = (i) ->
      now = Date.now()
      ms = now - i * ONE_DAY
      moment(ms).tz('America/Los_Angeles').format('YYYY-MM-DD')

    downloadFullPost = (id, callback) ->
      token = clientOnlyToken
      headers =
        "Accept": JSON_TYPE
        "Authorization": "Bearer #{token}"
      url = "https://api.producthunt.com/v1/posts/#{id}"
      cacheGet url, token, headers, (err, body) ->
        if err
          callback err
        else
          results = JSON.parse(body)
          callback null, results.post

    getPostsForDay = (day, callback) ->
      async.waterfall [
        (callback) ->
          getPostIDs clientOnlyToken, day, (err, ids) ->
            if err
              callback err
            else
              callback null, ids
        (ids, callback) ->
          async.map ids, downloadFullPost, (err, posts) ->
            if err
              callback err
            else
              callback null, posts

      ], callback

    days = _.map([0..6], daysAgoToSFDay)

    gpfdmstart = Date.now()

    async.map days, getPostsForDay, (err, postses) ->
      if err
        callback err
      else
        posts = _.flatten postses
        console.log "#{Date.now() - gpfdmstart} to retrieve #{posts.length} posts"
        callback null, posts, days

module.exports = getRecentPosts
