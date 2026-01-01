"""Light control operations using pywizlight."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Tuple, Dict, Any

from pywizlight import wizlight, PilotBuilder

from wizctl.config import get_light_by_name, load_config, LightConfig


class LightState(str, Enum):
    """Light power state."""

    ON = "on"
    OFF = "off"
    UNKNOWN = "unknown"


@dataclass
class LightStatus:
    """Current status of a light."""

    ip: str
    name: Optional[str]
    state: LightState
    brightness: Optional[int]  # 0-255
    temperature: Optional[int]  # Kelvin
    rgb: Optional[Tuple[int, int, int]]
    scene: Optional[str]
    mac: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "ip": self.ip,
            "name": self.name,
            "state": self.state.value,
            "brightness": self.brightness,
            "brightness_percent": round(self.brightness / 255 * 100) if self.brightness else None,
            "temperature": self.temperature,
            "rgb": list(self.rgb) if self.rgb else None,
            "scene": self.scene,
            "mac": self.mac,
        }


class LightController:
    """Controller for individual WiZ light operations."""

    def __init__(self, ip: str):
        """Initialize controller for a light.
        
        Args:
            ip: IP address of the light.
        """
        self.ip = ip
        self._bulb = wizlight(ip)

    async def close(self) -> None:
        """Close the bulb connection to prevent event loop errors."""
        try:
            if hasattr(self._bulb, 'async_close'):
                await self._bulb.async_close()
            elif hasattr(self._bulb, 'transport') and self._bulb.transport:
                self._bulb.transport.close()
            # Clear the loop reference to prevent __del__ errors
            if hasattr(self._bulb, 'loop'):
                self._bulb.loop = None
        except Exception:
            pass

    @classmethod
    def from_name(cls, name: str) -> LightController:
        """Create controller from light name/alias.
        
        Args:
            name: Light name, alias, or IP address.
            
        Returns:
            LightController instance.
            
        Raises:
            ValueError: If light not found.
        """
        light = get_light_by_name(name)
        if light:
            return cls(light.ip)
        
        # Assume it's an IP address
        if "." in name:
            return cls(name)
            
        raise ValueError(f"Light not found: {name}")

    async def get_status(self) -> LightStatus:
        """Get current light status.
        
        Returns:
            LightStatus with current state.
        """
        try:
            state = await self._bulb.updateState()
            
            # Get name from config
            config = load_config()
            name = None
            for light_name, light in config.lights.items():
                if light.ip == self.ip:
                    name = light.alias or light_name
                    break
            
            return LightStatus(
                ip=self.ip,
                name=name,
                state=LightState.ON if state.get_state() else LightState.OFF,
                brightness=state.get_brightness(),
                temperature=state.get_colortemp(),
                rgb=state.get_rgb(),
                scene=state.get_scene(),
                mac=self._bulb.mac,
            )
        except Exception as e:
            raise ConnectionError(f"Failed to get status for {self.ip}: {e}") from e

    async def turn_on(self, brightness: Optional[int] = None) -> bool:
        """Turn the light on.
        
        Args:
            brightness: Optional brightness (0-255).
            
        Returns:
            True if successful.
        """
        try:
            if brightness is not None:
                await self._bulb.turn_on(PilotBuilder(brightness=brightness))
            else:
                await self._bulb.turn_on()
            return True
        except Exception as e:
            raise ConnectionError(f"Failed to turn on {self.ip}: {e}") from e

    async def turn_off(self) -> bool:
        """Turn the light off.
        
        Returns:
            True if successful.
        """
        try:
            await self._bulb.turn_off()
            return True
        except Exception as e:
            raise ConnectionError(f"Failed to turn off {self.ip}: {e}") from e

    async def toggle(self) -> LightState:
        """Toggle the light on/off.
        
        Returns:
            New state after toggle.
        """
        status = await self.get_status()
        if status.state == LightState.ON:
            await self.turn_off()
            return LightState.OFF
        else:
            await self.turn_on()
            return LightState.ON

    async def set_brightness(self, brightness: int) -> bool:
        """Set light brightness.
        
        Args:
            brightness: Brightness value (0-255) or percentage (will convert).
            
        Returns:
            True if successful.
        """
        # Convert percentage to 0-255 if needed
        if brightness <= 100:
            brightness = int(brightness * 255 / 100)
        
        brightness = max(0, min(255, brightness))
        
        try:
            await self._bulb.turn_on(PilotBuilder(brightness=brightness))
            return True
        except Exception as e:
            raise ConnectionError(f"Failed to set brightness on {self.ip}: {e}") from e

    async def set_color(self, r: int, g: int, b: int, brightness: Optional[int] = None) -> bool:
        """Set light color (RGB).
        
        Args:
            r: Red value (0-255).
            g: Green value (0-255).
            b: Blue value (0-255).
            brightness: Optional brightness (0-255).
            
        Returns:
            True if successful.
        """
        r = max(0, min(255, r))
        g = max(0, min(255, g))
        b = max(0, min(255, b))
        
        try:
            builder = PilotBuilder(rgb=(r, g, b))
            if brightness is not None:
                builder = PilotBuilder(rgb=(r, g, b), brightness=brightness)
            await self._bulb.turn_on(builder)
            return True
        except Exception as e:
            raise ConnectionError(f"Failed to set color on {self.ip}: {e}") from e

    async def set_temperature(self, kelvin: int, brightness: Optional[int] = None) -> bool:
        """Set color temperature.
        
        Args:
            kelvin: Color temperature in Kelvin (2200-6500).
            brightness: Optional brightness (0-255).
            
        Returns:
            True if successful.
        """
        kelvin = max(2200, min(6500, kelvin))
        
        try:
            builder = PilotBuilder(colortemp=kelvin)
            if brightness is not None:
                builder = PilotBuilder(colortemp=kelvin, brightness=brightness)
            await self._bulb.turn_on(builder)
            return True
        except Exception as e:
            raise ConnectionError(f"Failed to set temperature on {self.ip}: {e}") from e

    async def set_scene(self, scene_id: int) -> bool:
        """Set a built-in WiZ scene.
        
        Args:
            scene_id: WiZ scene ID (1-32).
            
        Returns:
            True if successful.
        """
        try:
            await self._bulb.turn_on(PilotBuilder(scene=scene_id))
            return True
        except Exception as e:
            raise ConnectionError(f"Failed to set scene on {self.ip}: {e}") from e


# Synchronous wrappers for CLI use

async def _run_with_cleanup(controller: LightController, coro):
    """Run a coroutine and ensure controller cleanup."""
    try:
        return await coro
    finally:
        await controller.close()


def get_status_sync(name_or_ip: str) -> LightStatus:
    """Synchronous wrapper to get light status."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.get_status()))


def turn_on_sync(name_or_ip: str, brightness: Optional[int] = None) -> bool:
    """Synchronous wrapper to turn on a light."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.turn_on(brightness)))


def turn_off_sync(name_or_ip: str) -> bool:
    """Synchronous wrapper to turn off a light."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.turn_off()))


def toggle_sync(name_or_ip: str) -> LightState:
    """Synchronous wrapper to toggle a light."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.toggle()))


def set_brightness_sync(name_or_ip: str, brightness: int) -> bool:
    """Synchronous wrapper to set brightness."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.set_brightness(brightness)))


def set_color_sync(name_or_ip: str, r: int, g: int, b: int, brightness: Optional[int] = None) -> bool:
    """Synchronous wrapper to set color."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.set_color(r, g, b, brightness)))


def set_temperature_sync(name_or_ip: str, kelvin: int, brightness: Optional[int] = None) -> bool:
    """Synchronous wrapper to set temperature."""
    controller = LightController.from_name(name_or_ip)
    return asyncio.run(_run_with_cleanup(controller, controller.set_temperature(kelvin, brightness)))
