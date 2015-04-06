# accesstoken.coffee

{DatabankObject} = require 'databank'

AccessToken = DatabankObject.subClass 'AccessToken'

AccessToken.schema =
  pkey: "user"
  fields: [
    "token"
  ]
  indices: ["token"]

module.exports = AccessToken
