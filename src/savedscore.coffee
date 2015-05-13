# SavedScore.coffee

_ = require 'lodash'
{DatabankObject} = require 'databank'

SavedScore = DatabankObject.subClass 'SavedScore'

SavedScore.schema =
  pkey: "key"
  fields: [
    "postID"
    "inputs"
    "version"
    "outputs"
    "createdAt"
  ]

SavedScore.pkey = () ->
  "key"

SavedScore.makeKey = (postID, inputs, version) ->
  # Get values array in guaranteed order
  keys = _.keys inputs
  keys.sort()
  values = keys.map (key) -> inputs[key]
  "#{postID}|#{values.join(',')}|#{version}"

SavedScore.beforeCreate = (props, callback) ->
  if !props.postID
    return callback new Error("No postID")
  if !props.inputs
    return callback new Error("No inputs")
  if !props.version
    return callback new Error("No version")
  if !props.outputs
    return callback new Error("No outputs")

  props.key = SavedScore.makeKey props.postID, props.inputs, props.version
  props.createdAt = (new Date()).toISOString()
  callback null, props

SavedScore::beforeUpdate = (props, callback) ->
  callback new Error("Immutable object")

SavedScore::beforeSave = (callback) ->
  if @createdAt
    return callback new Error("Immutable object")
  SavedScore.beforeCreate @, (err) ->
    callback err

SavedScore.byPostInputsAndVersion = (postID, inputs, version, callback) ->
  key = SavedScore.makeKey postID, inputs, version
  SavedScore.get key, (err, score) ->
    if err && err.name == "NoSuchThingError"
      callback null, null
    else if err
      callback err
    else
      callback null, score

module.exports = SavedScore
