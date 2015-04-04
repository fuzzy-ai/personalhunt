express = require('express')
router = express.Router()

router.get '/', (req, res) ->
  res.render 'index', title: 'Welcome'
  return

router.get '/home', (req, res, next) ->
  res.render 'home', title: 'Home'

router.get '/settings', (req, res, next) ->
  res.render 'settings', title: 'Settings'

module.exports = router
