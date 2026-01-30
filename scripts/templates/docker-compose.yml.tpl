services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    restart: unless-stopped
    privileged: true
    network_mode: host
    volumes:
      - {{DATA_DIR}}/homeassistant:/config
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      - mosquitto

  mosquitto:
    container_name: mosquitto
    image: eclipse-mosquitto:2
    restart: unless-stopped
    ports:
      - "1883:1883"
    volumes:
      - {{DATA_DIR}}/mosquitto/config:/mosquitto/config
      - {{DATA_DIR}}/mosquitto/data:/mosquitto/data
      - {{DATA_DIR}}/mosquitto/log:/mosquitto/log

  # BEGIN zigbee2mqtt
  zigbee2mqtt:
    container_name: zigbee2mqtt
    image: koenkk/zigbee2mqtt
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - {{DATA_DIR}}/zigbee2mqtt:/app/data
      - /run/udev:/run/udev:ro
    devices:
      - {{ZIGBEE_DEVICE}}:/dev/ttyUSB0
    depends_on:
      - mosquitto
    environment:
      - TZ={{TZ}}
  # END zigbee2mqtt
