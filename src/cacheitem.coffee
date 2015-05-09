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

CacheItem.create = (props, callback) ->
  props.key = "#{token}|#{url}"
  props.createdAt = props.updatedAt = (new Date()).toISOString()
  callback null, props

CacheItem::update = (props, callback) ->
  props.updatedAt = (new Date()).toISOString()
  callback null, props

CacheItem::save = (callback) ->
  if !@key
    @key = "#{@token}|#{@url}"
  @updatedAt = (new Date()).toISOString()
  if !@createdAt
    @createdAt = @updatedAt
  callback null

CacheItem.byUrlAndToken = (url, token, callback) ->
  key = "#{token}|#{url}"
  CacheItem.get key, (err, cacheItem) ->
    if err
      if err.name == "NoSuchThingError"
        callback null, null
      else
        callback err
    else
      callback null, cacheItem

module.exports = CacheItem
