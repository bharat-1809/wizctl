"""Light discovery using pywizlight."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Dict, List, Optional

from pywizlight import discovery, wizlight

from wizctl.config import LightConfig, load_config, save_config


@dataclass
class DiscoveredLight:
    ip: str
    mac: str
    name: Optional[str] = None
    model: Optional[str] = None


class LightDiscovery:
    def __init__(self, broadcast_address: str = "255.255.255.255"):
        self.broadcast_address = broadcast_address

    async def discover(self, timeout: float = 5.0) -> List[DiscoveredLight]:
        """Discover WiZ lights on the network."""
        bulbs = await discovery.discover_lights(
            broadcast_space=self.broadcast_address,
            wait_time=timeout,
        )

        discovered = []
        for bulb in bulbs:
            try:
                await bulb.updateState()
                mac = bulb.mac or "unknown"
                model = bulb.bulbtype.name if bulb.bulbtype else None
                discovered.append(DiscoveredLight(ip=bulb.ip, mac=mac, model=model))
            except Exception:
                discovered.append(DiscoveredLight(
                    ip=bulb.ip,
                    mac=getattr(bulb, "mac", "unknown") or "unknown",
                ))
            finally:
                await self._close_bulb(bulb)

        return discovered

    @staticmethod
    async def _close_bulb(bulb) -> None:
        try:
            if hasattr(bulb, 'async_close'):
                await bulb.async_close()
            elif hasattr(bulb, 'transport') and bulb.transport:
                bulb.transport.close()
        except Exception:
            pass

    async def discover_and_save(self, timeout: float = 5.0) -> List[DiscoveredLight]:
        """Discover lights and save new ones to config."""
        discovered = await self.discover(timeout)
        config = load_config()

        new_lights = []
        for light in discovered:
            existing = any(
                l.ip == light.ip or l.mac == light.mac
                for l in config.lights.values()
            )
            if not existing:
                name = f"light_{light.ip.replace('.', '_')}"
                config.lights[name] = LightConfig(ip=light.ip, mac=light.mac)
                new_lights.append(light)

        if new_lights:
            save_config(config)

        return new_lights

    @staticmethod
    async def get_light_state(ip: str) -> dict:
        bulb = wizlight(ip)
        state = await bulb.updateState()
        result = {
            "ip": ip,
            "on": state.get_state(),
            "brightness": state.get_brightness(),
            "temperature": state.get_colortemp(),
            "rgb": state.get_rgb(),
            "scene": state.get_scene(),
        }
        if bulb.mac:
            result["mac"] = bulb.mac
        return result

    @staticmethod
    def get_cached_lights() -> Dict[str, LightConfig]:
        return load_config().lights


def discover_lights_sync(broadcast_address: str = "255.255.255.255", timeout: float = 5.0) -> List[DiscoveredLight]:
    return asyncio.run(LightDiscovery(broadcast_address).discover(timeout))


def discover_and_save_sync(broadcast_address: str = "255.255.255.255", timeout: float = 5.0) -> List[DiscoveredLight]:
    return asyncio.run(LightDiscovery(broadcast_address).discover_and_save(timeout))
