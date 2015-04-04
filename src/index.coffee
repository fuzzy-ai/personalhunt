express = require('express')
router = express.Router()
dummy = require "./dummy"

router.get '/', (req, res) ->
  res.render 'index', title: 'Welcome'
  return

router.get '/home', (req, res, next) ->
  res.render 'home',
    posts: dummy.posts.posts
    title: 'Home'

router.get '/about', (req, res, next) ->
  res.render 'about', title: 'About'

router.get '/settings', (req, res, next) ->
  res.render 'settings', title: 'Settings'

module.exports = router
