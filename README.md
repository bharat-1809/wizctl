# wizctl

Control Philips WiZ smart lights from the command line or REST API.

## Features

- Auto-discover WiZ lights on local network
- Full control: on/off, brightness, RGB color, color temperature
- Group and scene support

## Installation

```bash
python -m venv venv
source venv/bin/activate
pip install -e .
```

## Quick Start

```bash
# Discover lights on your network
wizctl discover

# List discovered lights
wizctl list

# Control a light
wizctl on 192.168.1.100
wizctl off 192.168.1.100
wizctl brightness 192.168.1.100 50
wizctl color 192.168.1.100 255 100 50
wizctl temp 192.168.1.100 3000
wizctl scene 192.168.1.100 Cozy

# Set a friendly alias
wizctl alias light_192_168_1_100 "Living Room"
wizctl on "Living Room"
```

## CLI Commands

```
wizctl discover              Discover lights on the network
wizctl list                  List configured lights
wizctl status <light>        Get light status

wizctl on <light>            Turn on
wizctl off <light>           Turn off
wizctl toggle <light>        Toggle on/off
wizctl brightness <light> N  Set brightness (0-100)
wizctl color <light> R G B   Set RGB color
wizctl temp <light> K        Set color temperature (2200-6500)
wizctl scene <light> NAME    Apply a scene
wizctl scenes                List available scenes

wizctl group list            List groups
wizctl group on <group>      Turn on group
wizctl group off <group>     Turn off group

wizctl serve                 Start REST API server
```

## REST API

```bash
wizctl serve --port 8000
```

Endpoints:

```
GET  /lights                 List all lights
POST /lights/discover        Discover new lights
GET  /lights/{id}            Get light status
POST /lights/{id}/on         Turn on
POST /lights/{id}/off        Turn off
POST /lights/{id}/toggle     Toggle
PUT  /lights/{id}/brightness Set brightness
PUT  /lights/{id}/color      Set RGB color
PUT  /lights/{id}/temperature Set temperature
POST /lights/{id}/scene      Apply scene
GET  /scenes                 List scenes
GET  /groups                 List groups
POST /groups/{name}/on       Turn on group
POST /groups/{name}/off      Turn off group
```

API docs available at `http://localhost:8000/docs`

### Example

```bash
curl -X POST http://localhost:8000/lights/192.168.1.100/on

curl -X PUT http://localhost:8000/lights/192.168.1.100/brightness \
  -H "Content-Type: application/json" \
  -d '{"value": 50}'
```

## Configuration

Edit `config/lights.yaml`:

```yaml
lights:
  living_room:
    ip: "192.168.1.100"
    alias: "Living Room"

groups:
  all: ["*"]
  bedroom: ["bedroom_main", "bedroom_lamp"]

scenes:
  movie:
    brightness: 20
    temperature: 2700
  work:
    brightness: 100
    temperature: 6500
```

## Built-in Scenes

Ocean, Romance, Sunset, Party, Fireplace, Cozy, Forest, Pastel Colors,
Wake Up, Bedtime, Warm White, Daylight, Cool White, Night Light, Focus,
Relax, True Colors, TV Time, Plant Growth, Spring, Summer, Fall,
Deep Dive, Jungle, Mojito, Club, Christmas, Halloween, Candlelight,
Golden White, Pulse, Steampunk

## Troubleshooting

**Lights not discovered?**
- Check lights are on the same network
- Try: `wizctl discover -b 192.168.1.255` (your subnet broadcast)
- Ensure UDP port 38899 isn't blocked

**Connection timeout?**
- Verify light is powered on
- Check IP address is correct
- Ensure no firewall blocking UDP

## License

MIT
