"""Light discovery functionality using pywizlight."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Dict, List, Optional

from pywizlight import discovery, wizlight

from wizctl.config import Config, LightConfig, load_config, save_config


@dataclass
class DiscoveredLight:
    """Represents a discovered WiZ light."""

    ip: str
    mac: str
    name: Optional[str] = None
    model: Optional[str] = None


class LightDiscovery:
    """Handles discovery of WiZ lights on the network."""

    def __init__(self, broadcast_address: str = "255.255.255.255"):
        """Initialize discovery with optional broadcast address.
        
        Args:
            broadcast_address: Network broadcast address for discovery.
                              Use your subnet's broadcast (e.g., "192.168.1.255")
                              for faster discovery.
        """
        self.broadcast_address = broadcast_address

    async def discover(self, timeout: float = 5.0) -> List[DiscoveredLight]:
        """Discover all WiZ lights on the network.
        
        Args:
            timeout: How long to wait for responses (seconds).
            
        Returns:
            List of discovered lights.
        """
        bulbs = await discovery.discover_lights(
            broadcast_space=self.broadcast_address,
            wait_time=timeout,
        )

        discovered = []
        for bulb in bulbs:
            # Get bulb info
            try:
                await bulb.updateState()
                mac = bulb.mac or "unknown"
                
                # Try to get model info
                model = None
                if bulb.bulbtype:
                    model = bulb.bulbtype.name
                    
                discovered.append(
                    DiscoveredLight(
                        ip=bulb.ip,
                        mac=mac,
                        name=None,  # User can set alias later
                        model=model,
                    )
                )
            except Exception:
                # Still add if we can't get full info
                discovered.append(
                    DiscoveredLight(
                        ip=bulb.ip,
                        mac=getattr(bulb, "mac", "unknown") or "unknown",
                    )
                )
            finally:
                # Close bulb connection to prevent event loop errors on cleanup
                await self._close_bulb(bulb)

        return discovered
    
    @staticmethod
    async def _close_bulb(bulb) -> None:
        """Safely close a bulb connection."""
        try:
            if hasattr(bulb, 'async_close'):
                await bulb.async_close()
            elif hasattr(bulb, 'transport') and bulb.transport:
                bulb.transport.close()
        except Exception:
            pass  # Ignore cleanup errors

    async def discover_and_save(self, timeout: float = 5.0) -> List[DiscoveredLight]:
        """Discover lights and save to configuration.
        
        Args:
            timeout: How long to wait for responses.
            
        Returns:
            List of newly discovered lights.
        """
        discovered = await self.discover(timeout)
        config = load_config()

        new_lights = []
        for light in discovered:
            # Check if already in config (by IP or MAC)
            existing = False
            for existing_light in config.lights.values():
                if existing_light.ip == light.ip or existing_light.mac == light.mac:
                    existing = True
                    break

            if not existing:
                # Generate a name based on IP
                name = f"light_{light.ip.replace('.', '_')}"
                config.lights[name] = LightConfig(
                    ip=light.ip,
                    mac=light.mac,
                    alias=None,
                )
                new_lights.append(light)

        if new_lights:
            save_config(config)

        return new_lights

    @staticmethod
    async def get_light_state(ip: str) -> dict:
        """Get the current state of a light.
        
        Args:
            ip: IP address of the light.
            
        Returns:
            Dictionary with light state.
        """
        bulb = wizlight(ip)
        try:
            state = await bulb.updateState()
            
            result = {
                "ip": ip,
                "on": state.get_state(),
                "brightness": state.get_brightness(),
                "temperature": state.get_colortemp(),
                "rgb": state.get_rgb(),
                "scene": state.get_scene(),
            }
            
            # Get MAC if available
            if bulb.mac:
                result["mac"] = bulb.mac
                
            return result
        finally:
            # Clean up connection
            pass

    @staticmethod
    def get_cached_lights() -> Dict[str, LightConfig]:
        """Get all lights from the configuration cache.
        
        Returns:
            Dictionary of light name to config.
        """
        config = load_config()
        return config.lights


def discover_lights_sync(broadcast_address: str = "255.255.255.255", timeout: float = 5.0) -> List[DiscoveredLight]:
    """Synchronous wrapper for light discovery.
    
    Args:
        broadcast_address: Network broadcast address.
        timeout: Discovery timeout in seconds.
        
    Returns:
        List of discovered lights.
    """
    discovery_instance = LightDiscovery(broadcast_address)
    return asyncio.run(discovery_instance.discover(timeout))


def discover_and_save_sync(broadcast_address: str = "255.255.255.255", timeout: float = 5.0) -> List[DiscoveredLight]:
    """Synchronous wrapper for discover and save.
    
    Args:
        broadcast_address: Network broadcast address.
        timeout: Discovery timeout in seconds.
        
    Returns:
        List of newly discovered lights.
    """
    discovery_instance = LightDiscovery(broadcast_address)
    return asyncio.run(discovery_instance.discover_and_save(timeout))
