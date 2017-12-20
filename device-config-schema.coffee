module.exports = {
  title: "pimatic-tado device config schemas"
  TadoClimate: {
    title: "TadoClimate config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      zone:
        description: "Zone id"
        type: "integer"
        default: 1
      interval:
        description: "Interval in ms to interace with Tado web, the minimal reading interval should be 120000 (2 min)"
        type: "integer"
        default: 120000
    }
  TadoPresence: {
    title: "TadoPresence config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      deviceId:
        description: "Tado ID of the mobile device"
        type: "integer"
        default: 1
      interval:
        description: "Interval in ms to interace with Tado web, the minimal reading interval should be 120000 (2 min)"
        type: "integer"
        default: 120000
    }
}
