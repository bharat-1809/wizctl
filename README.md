# WiZ Light Controller (wizctl)

Control Philips WiZ smart lights from the command line or via REST API. Designed for AI agent integration and automation.

## Features

- **Light Discovery**: Auto-discover WiZ lights on your local network
- **CLI Control**: Full control from your terminal
- **REST API**: Programmatic access for AI agents and integrations
- **All Light Features**: On/off, brightness, RGB color, color temperature
- **Built-in Scenes**: 32 WiZ scenes (Cozy, Movie, Fireplace, etc.)
- **Custom Scenes**: Define your own scenes in YAML
- **Group Control**: Control multiple lights at once
- **Zero Cloud**: 100% local control via UDP

## Installation

```bash
# Clone the repository
cd smart_light

# Create virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install the package
pip install -e .

# Or install dependencies directly
pip install -r requirements.txt
```

## Quick Start

### 1. Discover Lights

First, discover WiZ lights on your network:

```bash
wizctl discover
```

### 2. List Lights

```bash
wizctl list
```

### 3. Control Lights

```bash
# Turn on/off
wizctl on light_192_168_1_100
wizctl off light_192_168_1_100

# Or use IP directly
wizctl on 192.168.1.100

# Toggle
wizctl toggle 192.168.1.100

# Set brightness (0-100%)
wizctl brightness 192.168.1.100 50

# Set color (RGB)
wizctl color 192.168.1.100 255 100 50

# Set color temperature (2200-6500K)
wizctl temp 192.168.1.100 3000

# Apply a scene
wizctl scene 192.168.1.100 "Cozy"
```

### 4. Set Aliases (Optional)

```bash
wizctl alias light_192_168_1_100 "Living Room"
wizctl on "Living Room"
```

## CLI Reference

### Discovery & Status

| Command | Description |
|---------|-------------|
| `wizctl discover` | Find WiZ lights on the network |
| `wizctl list` | List all configured lights |
| `wizctl status <light>` | Get current light state |

### Light Control

| Command | Description |
|---------|-------------|
| `wizctl on <light> [-b BRIGHTNESS]` | Turn on (optionally set brightness) |
| `wizctl off <light>` | Turn off |
| `wizctl toggle <light>` | Toggle on/off |
| `wizctl brightness <light> <0-100>` | Set brightness |
| `wizctl color <light> <R> <G> <B>` | Set RGB color |
| `wizctl temp <light> <KELVIN>` | Set color temperature |
| `wizctl scene <light> <SCENE>` | Apply a scene |

### Scenes

| Command | Description |
|---------|-------------|
| `wizctl scenes` | List all available scenes |
| `wizctl scene <light> <name>` | Apply scene to light |

### Groups

| Command | Description |
|---------|-------------|
| `wizctl group list` | List all groups |
| `wizctl group on <group>` | Turn on group |
| `wizctl group off <group>` | Turn off group |
| `wizctl group toggle <group>` | Toggle group |
| `wizctl group scene <group> <scene>` | Apply scene to group |

### Server

| Command | Description |
|---------|-------------|
| `wizctl serve [-p PORT]` | Start REST API server |

## REST API

Start the server:

```bash
wizctl serve --port 8000
```

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/lights` | List all lights |
| POST | `/lights/discover` | Discover new lights |
| GET | `/lights/{id}` | Get light status |
| POST | `/lights/{id}/on` | Turn on |
| POST | `/lights/{id}/off` | Turn off |
| POST | `/lights/{id}/toggle` | Toggle |
| PUT | `/lights/{id}/brightness` | Set brightness |
| PUT | `/lights/{id}/color` | Set RGB color |
| PUT | `/lights/{id}/temperature` | Set temperature |
| POST | `/lights/{id}/scene` | Apply scene |
| GET | `/scenes` | List scenes |
| GET | `/groups` | List groups |
| POST | `/groups/{name}/on` | Turn on group |
| POST | `/groups/{name}/off` | Turn off group |

### Interactive Docs

Visit `http://localhost:8000/docs` for Swagger UI documentation.

### Example API Usage

```bash
# Discover lights
curl -X POST http://localhost:8000/lights/discover

# List lights
curl http://localhost:8000/lights

# Turn on a light
curl -X POST http://localhost:8000/lights/192.168.1.100/on

# Set brightness to 50%
curl -X PUT http://localhost:8000/lights/192.168.1.100/brightness \
  -H "Content-Type: application/json" \
  -d '{"value": 50}'

# Set color to orange
curl -X PUT http://localhost:8000/lights/192.168.1.100/color \
  -H "Content-Type: application/json" \
  -d '{"r": 255, "g": 165, "b": 0}'

# Apply a scene
curl -X POST http://localhost:8000/lights/192.168.1.100/scene \
  -H "Content-Type: application/json" \
  -d '{"scene": "Cozy"}'
```

## AI Agent Integration

The API is designed for AI agent control. Example Python usage:

```python
import httpx

async def control_lights():
    async with httpx.AsyncClient(base_url="http://localhost:8000") as client:
        # Get all lights
        response = await client.get("/lights")
        lights = response.json()["lights"]
        
        # Turn on living room
        await client.post("/lights/living_room/on")
        
        # Set to warm, dim lighting
        await client.put("/lights/living_room/brightness", json={"value": 30})
        await client.put("/lights/living_room/temperature", json={"kelvin": 2700})
        
        # Or use a scene
        await client.post("/lights/living_room/scene", json={"scene": "Cozy"})
```

## Configuration

Configuration is stored in `config/lights.yaml`:

```yaml
# Discovered lights (auto-populated)
lights:
  light_192_168_1_100:
    ip: "192.168.1.100"
    alias: "Living Room"
    mac: "AA:BB:CC:DD:EE:FF"

# Light groups
groups:
  all: ["*"]  # Wildcard for all lights
  bedroom: ["bedroom_main", "bedroom_lamp"]
  living_room: ["living_room"]

# Custom scenes
scenes:
  movie:
    brightness: 20
    temperature: 2700
  work:
    brightness: 100
    temperature: 6500
  romantic:
    brightness: 30
    color: [255, 100, 100]
```

## Built-in Scenes

WiZ lights support 32 built-in scenes:

| ID | Scene | ID | Scene |
|----|-------|----|-------|
| 1 | Ocean | 17 | True Colors |
| 2 | Romance | 18 | TV Time |
| 3 | Sunset | 19 | Plant Growth |
| 4 | Party | 20 | Spring |
| 5 | Fireplace | 21 | Summer |
| 6 | Cozy | 22 | Fall |
| 7 | Forest | 23 | Deep Dive |
| 8 | Pastel Colors | 24 | Jungle |
| 9 | Wake Up | 25 | Mojito |
| 10 | Bedtime | 26 | Club |
| 11 | Warm White | 27 | Christmas |
| 12 | Daylight | 28 | Halloween |
| 13 | Cool White | 29 | Candlelight |
| 14 | Night Light | 30 | Golden White |
| 15 | Focus | 31 | Pulse |
| 16 | Relax | 32 | Steampunk |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `WIZCTL_CONFIG` | Path to config file (default: `config/lights.yaml`) |

## Troubleshooting

### Lights not discovered

1. Ensure your WiZ lights are connected to the same network
2. Try specifying your subnet broadcast: `wizctl discover -b 192.168.1.255`
3. Check firewall allows UDP on port 38899

### Connection timeout

WiZ lights communicate via UDP. Ensure:
- Lights are powered on
- No firewall blocking UDP traffic
- Using correct IP address

## License

MIT

