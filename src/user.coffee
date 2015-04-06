# User.coffee

{DatabankObject} = require 'databank'

User = DatabankObject.subClass 'User'

User.schema =
  pkey: "id"
  fields: [
    "token"
    "name"
    "headline"
    "created_at"
    "username"
    "website_url"
    "image_url"
    "profile_url"
  ]
  indices: [
    "username"
    "website_url"
  ]

User.ensure = (props, callback) ->
  User.get props.id, (err, user) ->
    if err and err.name = "NoSuchThingError"
      User.create props, callback
    else if err
      callback err
    else
      callback null, user

module.exports = User
