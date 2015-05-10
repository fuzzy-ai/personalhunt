# ClientOnlyToken.coffee

{DatabankObject} = require 'databank'

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

module.exports = ClientOnlyToken
