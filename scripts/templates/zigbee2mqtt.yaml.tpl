homeassistant: true
permit_join: false
frontend:
  port: 8080
mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://mosquitto:1883
serial:
  port: {{ZIGBEE_DEVICE}}
  adapter: zstack
advanced:
  log_level: info
  network_key: GENERATE
