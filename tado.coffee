module.exports = (env) ->

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'
  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'
  #require tado client
  retry = require 'bluebird-retry'
  commons = require('pimatic-plugin-commons')(env) 
  TadoClient = require('./TadoClient.coffee')(env) 
  #tadoClient = require './TadoClient.coffee'  
  
  class TadoPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      
      @base = commons.base @, 'TadoPlugin'
      @client = new TadoClient
      
      #connecting to tado web interface and acquiring home id
      @loginPromise =
        retry(() => @client.login(@config.loginname, @config.password),
        {
          throw_original: true
          max_tries: 10
          interval: 1000
          backoff: 2
          predicate: ( (err) -> 
                      try
                        env.logger.info(err.error || err)
                        return err.error != "invalid_grant"
                      catch
                        return true
                     )
        }
        ).then((connected) =>
          env.logger.info("Login established, connected with tado web interface")
          return @client.me().then( (home_info) =>
            env.logger.info("Connect to #{home_info.homes[0].name} with id: #{home_info.homes[0].id}")
            if @config.debug
              env.logger.debug(JSON.stringify(home_info))
            @setHome(home_info.homes[0])
            Promise.resolve(home_info)
          )
        ).catch((err) ->
          env.logger.error("Could not connect to tado web interface: ", (err.error_description || err))
          Promise.reject(err)
        )
    
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("TadoClimate", {
        configDef: deviceConfigDef.TadoClimate,
        createCallback: (config, lastState) ->
          device = new TadoClimate(config, lastState)
          return device
      })
      
      @framework.deviceManager.registerDeviceClass("TadoPresence", {
        configDef: deviceConfigDef.TadoPresence,
        createCallback: (config, lastState) ->
          device = new TadoPresence(config, lastState)
          return device
      })
      
      @framework.deviceManager.on('discover', () =>
        #climate devices
        @loginPromise.then( (success) =>
          @framework.deviceManager.discoverMessage("pimatic-tado", "discovering zones..")
          return @client.zones(@home.id).then( (zones) =>
            id = null
            for zone in zones
              if zone.type = "HEATING" and zone.name != "Hot Water"
                id = @base.generateDeviceId @framework, zone.name, id
                config = {
                  class: 'TadoClimate'
                  id: id
                  zone: zone.id
                  name: zone.name
                  interval: 120000
                }
                @framework.deviceManager.discoveredDevice(
                  'pimatic-tado', 'TadoClimate: ' + config.name, config)
            Promise.resolve(true)
          )
        ).then ( (success) =>
          env.logger.info("test")
        ).catch ( (err) =>
          env.logger.error(err.error_description || err)
        )
      )
    
    setHome: (home) ->
      if home?
        @home = home
       
  plugin = new TadoPlugin

  class TadoClimate extends env.devices.TemperatureSensor
    _temperature: null
    _humidity: null

    attributes:
      temperature:
        description: "The measured temperature"
        type: "number"
        unit: '°C'
      humidity:
        description: "The actual degree of Humidity"
        type: "number"
        unit: '%'

    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @zone = @config.zone
      @_temperature = lastState?.temperature?.value
      @_humidity = lastState?.humidity?.value
      @lastState = null
      super()

      @requestClimate()
      @requestClimateIntervalId =
        setInterval( ( => @requestClimate() ), @config.interval)

    destroy: () ->
      clearInterval @requestClimateIntervalId if @requestClimateIntervalId?
      super()

    requestClimate: ->
      #if plugin.home?.id
      plugin.loginPromise
      .then( (success) =>
        return plugin.client.state(plugin.home.id, @zone)
        .then( (state) =>
          if @config.debug
            env.logger.debug("state received: #{JSON.stringify(state)}")
          @_temperature = state.sensorDataPoints.insideTemperature.celsius
          @_humidity = state.sensorDataPoints.humidity.percentage
          @emit "temperature", @_temperature
          @emit "humidity", @_humidity
          Promise.resolve(state)
        )        
      ).catch( (err) =>
        env.logger.error(err.error_description || err)
        if @config.debug
          env.logger.debug("homeId=:" + plugin.home.id)
        Promise.reject(err)
      )
     
    getTemperature: -> Promise.resolve(@_temperature)
    getHumidity: -> Promise.resolve(@_humidity)

  class TadoPresence extends env.devices.PresenceSensor 
    _presence: undefined
    _relativeDistance: null

    attributes:
      presence:
        description: "Presence of the human/device"
        type: "boolean"
        labels: ['present', 'absent']
      relativeDistance:
        description: "Relative distance of human/device from home"
        type: "number"
        unit: '%'
    
    constructor: (@config, lastState) ->
      @name = @config.name
      @id = @config.id
      @deviceId = @config.deviceId
      @_presence = lastState?.presence?.value or false
      @_relativeDistance = lastState?.relativeDistance?.value
      @lastState = null
      super()
      
      @requestPresence()
      @requestPresenceIntervalId =
        setInterval( ( => @requestPresence() ), @config.interval)

    destroy: () ->
      clearInterval @requestPresenceIntervalId if @requestPresenceIntervalId?
      super()

    requestPresence: ->
      #if plugin.home?.id
      plugin.loginPromise
      .then( (success) =>
        return plugin.client.mobileDevices(plugin.home.id)
        .then( (mobileDevices) =>
          env.logger.info("mobileDevices received: #{JSON.stringify(mobileDevices)}")
          for mobileDevice in mobileDevices
            if mobileDevice.id == @deviceId
              @_presence =  mobileDevice.location.atHome
              @_relativeDistance = mobileDevice.location.relativeDistanceFromHomeFence * 100
              @emit "temperature", @_presence
              @emit "relativeDistance", @_relativeDistance
          Promise.resolve(mobileDevices)
        )        
      ).catch( (err) =>
        env.logger.error(err)
        if @config.debug
          env.logger.debug("homeId=:" + plugin.home.id)
        Promise.reject(err)
      )
     
    getPresence: -> Promise.resolve(@_presence)
    getRelativeDistance: -> Promise.resolve(@_relativeDistance)
    
  return plugin
