# agent.coffee

assert = require 'assert'

async = require 'async'
_ = require 'lodash'

UserAgent = require './useragent'

agent =
  defaultAgent:
    inputs:
      relatedPostUpvotes:
        veryLow: [0, 1]
        low: [0, 1, 2]
        medium: [1, 2, 3]
        high: [2, 3, 4]
        veryHigh: [3, 4]
      relatedPostComments:
        veryLow: [0, 1]
        low: [0, 1, 2]
        medium: [1, 2, 3]
        high: [2, 3, 4]
        veryHigh: [3, 4]
      followingHunters:
        high: [0, 1, 2]
      followingMakers:
        high: [0, 1, 2]
        veryHigh: [1, 2]
      followingUpvotes:
        veryLow: [0, 12.5]
        low: [0, 12.5, 25]
        medium: [12.5, 25, 37.5]
        high: [25, 37.5, 50]
        veryHigh: [37.5, 50]
      followingComments:
        veryLow: [0, 1]
        low: [0, 1, 2]
        medium: [1, 2, 3]
        high: [2, 3, 4]
        veryHigh: [3, 4]
      totalUpvotes:
        veryLow: [0, 125]
        low: [0, 125, 250]
        medium: [125, 250, 375]
        high: [250, 375, 500]
        veryHigh: [375, 500]
      totalComments:
        veryLow: [0, 10]
        low: [0, 10, 20]
        medium: [10, 20, 30]
        high: [20, 30, 40]
        veryHigh: [30, 40]
    outputs:
      score:
        veryLow: [0, 25]
        low: [0, 25, 50]
        medium: [25, 50, 75]
        high: [50, 75, 100]
        veryHigh: [75, 100]
    rules: []

  defaultWeights: {}

  make: (weights) ->
    inst = _.cloneDeep(agent.defaultAgent)
    for input, inputSets of inst.inputs
      weight = weights[input]
      for inputSet, inputShape of inputSets
        for output, outputSets of inst.outputs
          if _.has(outputSets, inputSet)
            rule = "IF #{input} IS #{inputSet} THEN #{output} IS #{inputSet} WITH #{weight}"
            inst.rules.push rule
    inst

  makeDefault: (client, user, callback) ->
    inst = agent.make agent.defaultWeights
    async.waterfall [
      (callback) ->
        client.newAgent inst, callback
      (created, callback) ->
        UserAgent.create {user: user, agent: created.id, version: created.latestVersion}, callback
    ], callback

  update: (client, user, agentID, weights, callback) ->

    assert.ok _.isObject(client), "#{client} is not an object"
    assert.ok _.isObject(user), "#{user} is not an object"
    assert.ok _.isString(agentID), "#{agentID} is not a string"
    assert.ok _.isObject(weights), "#{weights} is not an object"

    newAgent = agent.make weights

    updated = null

    async.waterfall [
      (callback) ->
        client.putAgent agentID, newAgent, callback
      (results, callback) ->
        updated = results
        UserAgent.get user.id, callback
      (ua, callback) ->
        ua.version = updated.latestVersion
        ua.save callback
    ], (err) ->
      callback err


for input, value of agent.defaultAgent.inputs
  agent.defaultWeights[input] = 0.5

module.exports = agent
