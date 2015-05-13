# useragent.coffee

{DatabankObject} = require 'databank'

UserAgent = DatabankObject.subClass 'UserAgent'

UserAgent.schema =
  pkey: "user"
  fields: [
    "agent"
    "version"
    "createdAt"
    "updatedAt"
  ]
  indices: ["agent"]

UserAgent.beforeCreate = (props, callback) ->
  if !props.user
    return callback new Error("No user")
  if !props.agent
    return callback new Error("No agent")
  if !props.version
    return callback new Error("No version")
  props.createdAt = props.updatedAt = (new Date()).toISOString()
  callback null, props

UserAgent::beforeUpdate = (props, callback) ->
  props.updatedAt = (new Date()).toISOString()
  callback null, props

UserAgent::beforeSave = (callback) ->
  if !@user
    return callback new Error("No user")
  if !@agent
    return callback new Error("No agent")
  if !@version
    return callback new Error("No version")
  @updatedAt = (new Date()).toISOString()
  if !@createdAt
    @createdAt = @updatedAt
  callback null

module.exports = UserAgent
