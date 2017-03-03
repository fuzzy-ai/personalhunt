# ClientOnlyToken.coffee

_ = require 'lodash'
{DatabankObject} = require 'databank'
web = require 'fuzzy.ai-web'

JSON_TYPE = "application/json"

ClientOnlyToken = DatabankObject.subClass 'ClientOnlyToken'

ClientOnlyToken.schema =
  pkey: "clientID"
  fields: [
    "token"
    "expiresAt"
    "createdAt"
    "updatedAt"
  ]

ClientOnlyToken.beforeCreate = (props, callback) ->

  if !props.clientID
    return callback new Error("No clientID")

  if !props.token
    return callback new Error("No token")

  props.createdAt = props.updatedAt = (new Date()).toISOString()

  callback null, props

ClientOnlyToken::beforeUpdate = (props, callback) ->

  props.updatedAt = (new Date()).toISOString()

  callback null, props

ClientOnlyToken::beforeSave = (callback) ->

  @updatedAt = (new Date()).toISOString()

  if !@createdAt
    @createdAt = @updatedAt

  callback null

ClientOnlyToken::expired = ->
  @expiresAt? and (Date.parse(@expiresAt) < (Date.now() + ONE_HOUR))

ONE_HOUR = 1000 * 60 * 60

ClientOnlyToken::test = (callback) ->

  headers =
    "Accept": JSON_TYPE
    "Authorization": "Bearer #{@token}"

  url = "https://api.producthunt.com/v1/posts?per_page=1"

  web.get url, headers, (err, response, body) ->
    if err && err.statusCode == 401
      callback null, false
    else if err
      callback err
    else
      callback null, true

ClientOnlyToken.newToken = (clientID, clientSecret, callback) ->

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
      callback err
    else if response.statusCode != 200
      code = response.statusCode
      err = new Error("Status code #{code} posting to #{url}: #{body}")
      callback err
    else
      results = JSON.parse(body)
      if !cot?
        cot = new ClientOnlyToken({clientID: clientID})
      cot.token = results.access_token

      # XXX: expiration in seconds or milliseconds?
      if _.isNumber results.expires_in
        expiresAt = new Date(Date.now() + (results.expires_in * 1000))
        cot.expiresAt = expiresAt.toISOString()

      cot.save (err) ->
        if err
          callback err
        else
          callback null, cot.token

ClientOnlyToken.ensure = (clientID, clientSecret, callback) ->

  ClientOnlyToken.get clientID, (err, cot) ->
    if err
      if err.name is "NoSuchThingError"
        ClientOnlyToken.newToken clientID, clientSecret, callback
      else
        callback err
    else if cot.expired()
      ClientOnlyToken.newToken clientID, clientSecret, callback
    else
      cot.test (err, isValid) ->
        if err
          callback err
        else if !isValid
          ClientOnlyToken.newToken clientID, clientSecret, callback
        else
          callback null, cot.token

module.exports = ClientOnlyToken
