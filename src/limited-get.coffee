# limited-get.coffee
# Use rate-limiting to determine how fast to get requests

# How long to wait before making a request

async = require 'async'
web = require 'fuzzy.io-web'

debug = require('debug')('personalhunt:limited-get')

requestLimit = 900
requestLimitPeriod = 15 * 60 * 1000

requestsLeft = requestLimit
reset = Date.now() + requestLimitPeriod
noRequestUntil = null

toDate = (ms) ->
  dt = new Date(ms)
  dt.toISOString()

updateLimits = (headers) ->
  debug "Updating request limit info"
  if headers?
    debug "Have headers"
    if headers['x-rate-limit-limit']
      requestLimit = parseInt headers['x-rate-limit-limit'], 10
      debug "Updated requestLimit to #{requestLimit}"
    if headers['x-rate-limit-remaining']
      requestsLeft = parseInt headers['x-rate-limit-remaining'], 10
      debug "Updated requestsLeft to #{requestsLeft}"
    if headers['x-rate-limit-reset']
      reset = Date.now() +
        (parseInt(headers['x-rate-limit-reset'], 10) * 1000)
      debug "Updated reset to #{reset} (#{toDate(reset)})"

waitAndGet = (task, callback) ->
  {url, headers} = task

  debug "Handling #{url}"

  get = ->

    debug "Done waiting; getting #{url}"

    web.get url, headers, callback

  debug "noRequestUntil = #{noRequestUntil}"

  if noRequestUntil? and noRequestUntil > Date.now()
    wait = noRequestUntil - Date.now()
  else
    wait = 0

  if requestsLeft > 0
    # We have requests left this period
    if noRequestUntil?
      noRequestUntil += Math.ceil((reset - Date.now())/requestsLeft)
    else
      noRequestUntil = Date.now() + Math.ceil((reset - Date.now())/requestsLeft)
  else if !noRequestUntil? or noRequestUntil < reset
    # First one has to wait till the reset
    noRequestUntil = reset
  else
    # Others wait optimistically till after the reset
    noRequestUntil += requestLimitPeriod/requestLimit

  debug "Waiting #{wait} ms to get #{url}"

  setTimeout get, wait

q = async.queue waitAndGet, 4

limitedGet = (url, headers, callback) ->

  debug "Enqueuing #{url}"

  onResponse = (err, response, body) ->
    debug "Received response for #{url}"
    if err
      # On error, there's no response; get the headers
      # from the error
      updateLimits err.headers
      if err.statusCode == 429
        debug "Rate-limiting error; requeueing #{url}"
        q.push {url: url, headers: headers}, onResponse
      else
        callback err, response, body
    else
      debug "Successful request"
      updateLimits response.headers
      callback err, response, body

  q.push {url: url, headers: headers}, onResponse

debug "Initializing"

debug
  requestLimit: requestLimit
  requestLimitPeriod: requestLimitPeriod
  requestsLeft: requestsLeft
  reset: reset
  resetDate: toDate reset
  noRequestUntil: noRequestUntil
  secondsTillReset: Math.ceil((reset - Date.now())/1000)

module.exports = limitedGet
