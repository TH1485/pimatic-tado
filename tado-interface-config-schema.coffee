# #pimatic-tado configuration options
module.exports = {
  title: "tado plugin config options"
  type: "object"
  properties: {
    loginname:
      description:"Tado weblogin"
      type: "string"
      required: true
    password:
      description:"Tado webpassword"
      type: "string"
      required: true
    debug:
      description: "Log information for debugging, including received messages"
      type: "boolean"
      default: true
  } 
}
