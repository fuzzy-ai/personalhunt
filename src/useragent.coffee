# useragent.coffee

{DatabankObject} = require 'databank'

UserAgent = DatabankObject.subClass 'UserAgent'

UserAgent.schema =
  pkey: "user"
  fields: [
    "agent"
  ]
  indices: ["agent"]
  
module.exports = UserAgent
