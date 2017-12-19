# pimatic-tado


Tado interface for pimatic

Currently Support for:
- Tado temperature and humidity readout via the public preview api.

**This plugin is baesed on node-tado (https://github.com/dVelopment/node-tado)

###  Installation on Raspberry PI

```code
cd /home/pi/pimatic-app/node_modules
git clone https://github.com/TH1485/pimatic-tado.git
cd ./pimatic-tado
npm install
```

### Plugin Configuration

Add the plugin to the plugin section:

```json
{ 
  "plugin": "tado",
  "login" : "mylogin@email.com",
  "password" : "mypassword"
}
```
add manual to device section or use discover devices in the pimatic web interface!
```json
{
  "id": "mylivingroom",
  "name": "My Living Room",
  "class": "ZoneClimate",
  "zone": 1,
  "interval": 120000
 }
```
