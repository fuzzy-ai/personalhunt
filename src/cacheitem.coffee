# CacheItem.coffee

{DatabankObject} = require 'databank'

CacheItem = DatabankObject.subClass 'CacheItem'

CacheItem.schema =
  pkey: "urlAndToken"
  fields: [
    "url"
    "token"
    "etag"
    "body"
    "createdAt"
    "updatedAt"
  ]

CacheItem.pkey = () ->
  "urlAndToken"

makeKey = (url, token) ->
  "#{url}|#{token}"

CacheItem.beforeCreate = (props, callback) ->
  props.urlAndToken = makeKey props.url, props.token
  props.createdAt = props.updatedAt = (new Date()).toISOString()
  callback null, props

CacheItem::beforeUpdate = (props, callback) ->
  props.updatedAt = (new Date()).toISOString()
  callback null, props

CacheItem::beforeSave = (callback) ->
  if !@urlAndToken
    @urlAndToken = makeKey @url, @token
  @updatedAt = (new Date()).toISOString()
  if !@createdAt
    @createdAt = @updatedAt
  callback null

CacheItem.byUrlAndToken = (url, token, callback) ->
  urlAndToken = makeKey url, token
  CacheItem.get urlAndToken, (err, cacheItem) ->
    if err && err.name == "NoSuchThingError"
      callback null, null
    else if err
      callback err
    else
      callback null, cacheItem

module.exports = CacheItem
