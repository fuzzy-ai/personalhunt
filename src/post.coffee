# post.coffee

_ = require 'lodash'
{DatabankObject} = require 'databank'

Post = DatabankObject.subClass 'Post'

Post.schema =
  pkey: "id"
  fields: [
    "name"
    "tagline"
    "created_at"
    "day"
    "comments_count"
    "votes_count"
    "discussion_url"
    "redirect_url"
    "screenshot_url"
    "user"
    "makers"
    "current_user"
    "maker_inside"
  ]

Post.beforeCreate = (props, callback) ->

  User = require 'user'

  props.syncedAt = (new Date()).toISOString()

  async.waterfall [
    (callback) ->
      User.ensure props.user, (err, user) ->
        if err
          callback err
        else
          props.user = user.id
          callback null
    (callback) ->
      async.map props.makers, User.ensure, (err, makers) ->
        if err
          callback err
        else
          props.makers = _.map(makers, "id")
          callback null
  ], (err) ->
    if err
      callback err
    else
      callback null, props

Post.ensure = (props, callback) ->
  Post.get props.id, (err, post) ->
    if err and err.name = "NoSuchThingError"
      Post.create props, callback
    else if err
      callback err
    else
      callback null, post

module.exports = Post
