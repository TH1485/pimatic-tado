module.exports = (env) ->

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'
  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'
  #require tado client
  retry = require 'bluebird-retry'
  commons = require('pimatic-plugin-commons')(env) 
  tadoClient = require('./tadoClient.coffee')(env) 
  #tadoClient = require './tadoClient.coffee'  
  
  class TadoPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      
      @base = commons.base @, 'TadoPlugin'
      @client = new tadoClient
      
      #connecting to tado web interface and acquiring home id
      @loginPromise =
        retry(() => @client.login(@config.loginname, @config.password),
        {
          max_tries: 10
          interval: 100
          backoff: 2
          predicate: ( (err) -> return JSON.parse(err.failure).error != "invalid_grant") 
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
          env.logger.error("Could not connect to tado web interface", err)
          if err.response? 
            env.logger.error("statusCode:"+ err.response.statusCode)
          Promise.reject(err)
        )
    
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("ZoneClimate", {
        configDef: deviceConfigDef.ZoneClimate,
        createCallback: (config, lastState) ->
          device = new ZoneClimate(config, lastState)
          return device
      })
      
      @framework.deviceManager.on('discover', () =>
        @loginPromise.then( (success) =>
          @framework.deviceManager.discoverMessage("pimatic-tado", "discovering zones..")
          return @client.zones(@home.id).then( (zones) =>
            id = null
            for zone in zones
              if zone.type = "HEATING" and zone.name != "Hot Water"
                id = @base.generateDeviceId @framework, zone.name, id
                config = {
                  class: 'ZoneClimate'
                  id: id
                  zone: zone.id
                  name: zone.name
                  interval: 120000
                }
                @framework.deviceManager.discoveredDevice(
                  'pimatic-tado', 'ZoneClimate: ' + config.name, config
              )
            Promise.resolve(zones)
          )
        ).catch ( (err) =>
          env.logger.error(err)
        )
      )     
                
    
    setHome: (home) ->
      if home?
        @home = home
       
  plugin = new TadoPlugin

  class ZoneClimate extends env.devices.TemperatureSensor
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
      super()

      @requestValue()
      @requestValueIntervalId =
        setInterval( ( => @requestValue() ), @config.interval)

    destroy: () ->
      clearInterval @requestValueIntervalId if @requestValueIntervalId?
      super()

    requestValue: ->
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
        env.logger.error(err)
        if @config.debug
          env.logger.debug("homeId=:" + plugin.home.id)
        Promise.reject(err)
      )
     
    getTemperature: -> Promise.resolve(@_temperature)
    getHumidity: -> Promise.resolve(@_humidity)

  
  return plugin
