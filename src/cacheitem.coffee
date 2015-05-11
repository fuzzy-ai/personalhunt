# CacheItem.coffee

{DatabankObject} = require 'databank'

CacheItem = DatabankObject.subClass 'CacheItem'

CacheItem.schema =
  pkey: "urlAndToken"
  fields: [
    "url"
    "token"
    "lastModified"
    "etag"
    "createdAt"
    "updatedAt"
  ]

CacheItem.beforeCreate = (props, callback) ->
  props.urlAndToken = "#{token}|#{url}"
  props.createdAt = props.updatedAt = (new Date()).toISOString()
  callback null, props

CacheItem::beforeUpdate = (props, callback) ->
  props.updatedAt = (new Date()).toISOString()
  callback null, props

CacheItem::beforeSave = (callback) ->
  if !@urlAndToken
    @urlAndToken = "#{@token}|#{@url}"
  @updatedAt = (new Date()).toISOString()
  if !@createdAt
    @createdAt = @updatedAt
  callback null

CacheItem.byUrlAndToken = (url, token, callback) ->
  urlAndToken = "#{token}|#{url}"
  CacheItem.get urlAndToken, (err, cacheItem) ->
    if err
      if err.name == "NoSuchThingError"
        callback null, null
      else
        callback err
    else
      callback null, cacheItem

module.exports = CacheItem
