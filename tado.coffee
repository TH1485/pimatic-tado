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
      @loginPromise = Promise.reject(new Error('tado is not logged in (yet)!'))
      # wait for pimatic to finish starting http(s) server
      @framework.once "server listen", =>
        env.logger.info("Pimatic server started, initializing tado connection") 
        #connecting to tado web interface and acquiring home id  
        @loginPromise =
          retry( () => @client.login(@config.loginname, @config.password),
          {
          throw_original: true
          max_tries: 20
          interval: 50
          backoff: 2
          predicate: (err) ->
            try
              if @config.debug
                env.logger.debug(err.error || (err.code || err))
              return err.error != "invalid_grant"
            catch
              return true
          }
          ).then (connected) =>
            env.logger.info("Login established, connected with tado web interface")
            return @client.me().then (home_info) =>
              env.logger.info("Connected to #{home_info.homes[0].name} with id: #{home_info.homes[0].id}")
              if @config.debug
                env.logger.debug(JSON.stringify(home_info))
              @setHome(home_info.homes[0])
              connected
          .catch (err) ->
            env.logger.error("Could not connect to tado web interface: #{(err.error_description || (err.code || err) )}")
            Promise.reject err
      #
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("TadoClimate", {
        configDef: deviceConfigDef.TadoClimate,
        createCallback: (config, lastState) =>
          device = new TadoClimate(config, lastState,@framework)
          return device
      })

      @framework.deviceManager.registerDeviceClass("TadoPresence", {
        configDef: deviceConfigDef.TadoPresence,
        createCallback: (config, lastState) =>
          device = new TadoPresence(config, lastState,@framework)
          return device
      })

      @framework.deviceManager.on 'discover', () =>
        #climate devices
        @loginPromise
        .then (success) =>
          @framework.deviceManager.discoverMessage("pimatic-tado", "discovering devices..")
          return @client.zones(@home.id)
          .then (zones) =>
            id = null
            for zone in zones
              if zone.type = 'HEATING' and zone.name != 'Hot Water'
                id = @base.generateDeviceId @framework, zone.name.toLowerCase(), id
                id = id.toLowerCase().replace(/\s/g,'')
                config =
                  class: 'TadoClimate'
                  id: id
                  zone: zone.id
                  name: zone.name
                  interval: 120000
                @framework.deviceManager.discoveredDevice(
                  'TadoClimate', config.name, config)
            Promise.resolve(true)
          , (err) ->
            env.logger.error(err.error_description || err)
            Promise.reject(err)
        .then (success) =>
          return @client.mobileDevices(@home.id)
          .then (mobileDevices) =>
            id = null
            for mobileDevice in mobileDevices
              if mobileDevice.settings.geoTrackingEnabled
                id = @base.generateDeviceId @framework, mobileDevice.name, id
                id = id.toLowerCase().replace(/\s/g,'')
                config =
                  class: 'TadoPresence'
                  id: id
                  deviceId: mobileDevice.id
                  name: mobileDevice.name
                  interval: 120000
                @framework.deviceManager.discoveredDevice(
                  'TadoPresence', config.name, config)
            Promise.resolve(true)
          , (err) ->
            env.logger.error(err.error_description || err)
            Promise.reject(err)
        .catch (err) ->
          env.logger.error(err.error_description || err)
          Promise.reject(err)

    
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

    constructor: (@config, lastState,@framework) ->
      @name = @config.name
      @id = @config.id
      @zone = @config.zone
      @_temperature = lastState?.temperature?.value
      @_humidity = lastState?.humidity?.value
      @_timestampTemp = null
      @_timestampHum = null
      @lastState = null
      super()

      
      @requestClimate()
      @requestClimateIntervalId =
        setInterval( ( => @requestClimate() ), @config.interval)

    destroy: () ->
      clearInterval @requestClimateIntervalId if @requestClimateIntervalId?
      super()

    requestClimate: ->
      if plugin.loginPromise? and plugin.home?.id
        plugin.loginPromise
        .then (success) =>
          return plugin.client.state(plugin.home.id, @zone)
          .then (state) =>
            if @config.debug
              env.logger.debug("state received: #{JSON.stringify(state)}")
            if state.sensorDataPoints.insideTemperature.timestamp != @_timestampTemp
              @_temperature = state.sensorDataPoints.insideTemperature.celsius
              @emit "temperature", @_temperature
            if state.sensorDataPoints.humidity.timestamp != @_timestampHum
              @_humidity = state.sensorDataPoints.humidity.percentage
              @emit "humidity", @_humidity
            Promise.resolve(state)
        .catch (err) =>
          env.logger.error(err.error_description || (err.code || err) )
          if @config.debug
            env.logger.debug("homeId=:" + plugin.home.id)
          Promise.reject(err)
           
    getTemperature: -> Promise.resolve(@_temperature)
    getHumidity: -> Promise.resolve(@_humidity)

  class TadoPresence extends env.devices.PresenceSensor
    _presence: undefined
    _relativeDistance: null

    attributes:
      presence:
        description: "Presence of the human/device"
        type: "boolean"
        labels: ['Home', 'Away']
      relativeDistance:
        description: "Relative distance of human/device from home"
        type: "number"
        unit: '%'

    constructor: (@config, lastState, @framework) ->
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
      if plugin.loginPromise? and plugin.home?.id
        plugin.loginPromise
        .then (success) =>
          return plugin.client.mobileDevices(plugin.home.id)
          .then (mobileDevices) =>
            if @config.debug
              env.logger.debug("mobileDevices received: #{JSON.stringify(mobileDevices)}")
            for mobileDevice in mobileDevices
              if mobileDevice.id == @deviceId
                @_presence =  mobileDevice.location.atHome
                @_relativeDistance = (1-mobileDevice.location.relativeDistanceFromHomeFence) * 100
                @emit "presence", @_presence
                @emit "relativeDistance", @_relativeDistance
            Promise.resolve(mobileDevices)
        .catch (err) =>
          env.logger.error(err.error_description || (err.code || err))
          if @config.debug
            env.logger.debug("homeId= #{plugin.home.id}")
          Promise.reject(err)

    getPresence: -> Promise.resolve(@_presence)
    getRelativeDistance: -> Promise.resolve(@_relativeDistance)

  return plugin
