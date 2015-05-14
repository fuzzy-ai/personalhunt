# ClientOnlyToken.coffee

{DatabankObject} = require 'databank'
web = require 'fuzzy.io-web'

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

  if !props.expiresAt
    return callback new Error("No expiresAt")

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

ONE_HOUR = 1000 * 60 * 60

ClientOnlyToken.ensure = (clientID, clientSecret, callback) ->

  ClientOnlyToken.get clientID, (err, cot) ->
    if err && err.name != "NoSuchThingError"
      callback err
    else
      if cot && Date.parse(cot.expiresAt) > (Date.now() + ONE_HOUR)
        callback null, cot.token
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
            callback err
          else if response.statusCode != 200
            err = new Error("Bad status code #{response.statusCode} posting to #{url}: #{body}")
            callback err
          else
            results = JSON.parse(body)
            if !cot?
              cot = new ClientOnlyToken({clientID: clientID})
            cot.token = results.access_token
            # XXX: expiration in seconds or milliseconds?
            cot.expiresAt = (new Date(Date.now() + (results.expires_in * 1000))).toISOString()
            cot.save (err) ->
              if err
                callback err
              else
                callback null, cot.token

module.exports = ClientOnlyToken
