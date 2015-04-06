fs = require "fs"

{print} = require "sys"
{spawn} = require "child_process"

glob = require "glob"
_ = require "lodash"

DOCKERIMAGE = "fuzzyio/personalhunt"

cmd = (str, env, callback) ->
  if _.isFunction(env)
    callback = env
    env = null
  env = _.defaults(env, process.env)
  parts = str.split(" ")
  main = parts[0]
  rest = parts.slice(1)
  proc = spawn main, rest, {env: env}
  proc.stderr.on "data", (data) ->
    process.stderr.write data.toString()
  proc.stdout.on "data", (data) ->
    print data.toString()
  proc.on "exit", (code) ->
    callback?() if code is 0

build = (callback) ->
  cmd "coffee -c -o lib src", callback

buildTest = (callback) ->
  cmd "coffee -c test", callback

buildDocker = (callback) ->
  cmd "sudo docker build -t #{DOCKERIMAGE} .", callback

push = (callback) ->
  cmd "sudo docker push #{DOCKERIMAGE}", callback

clean = (callback) ->
  patterns = ["lib/*.js", "test/*.js", "*~", "lib/*~", "src/*~", "test/*~"]
  for pattern in patterns
    glob pattern, (err, files) ->
      for file in files
        fs.unlinkSync file
  callback()

task "clean", "Clean up extra files", ->
  clean()

task "build", "Build lib/ from src/", ->
  clean ->
    build()

task "buildtest", "Build test", ->
  clean ->
    build ->
      buildTest()

task "test", "Test the API", ->
  clean ->
    build ->
      buildTest ->
        cmd "vows --spec test/*-test.js"

task "docker", "Build docker image", ->
  clean ->
    build ->
      buildDocker()

task "push", "Deploy to repository", ->
  push()

task "run", "Run the server", ->
  cmd "sudo docker-compose up"
