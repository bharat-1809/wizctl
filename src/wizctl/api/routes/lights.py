"""Light API routes."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException

from wizctl.api.models import (
    BrightnessRequest,
    ColorRequest,
    DiscoveryResponse,
    LightListResponse,
    LightResponse,
    SceneRequest,
    SuccessResponse,
    TemperatureRequest,
)
from wizctl.config import load_config
from wizctl.core.discovery import LightDiscovery
from wizctl.core.light import LightController
from wizctl.core.scenes import SceneManager

router = APIRouter(prefix="/lights", tags=["lights"])


@router.get("", response_model=LightListResponse)
async def list_lights():
    """List all configured lights."""
    config = load_config()
    lights = []
    
    for name, light in config.lights.items():
        lights.append(
            LightResponse(
                ip=light.ip,
                name=name,
                alias=light.alias,
                mac=light.mac,
            )
        )
    
    return LightListResponse(lights=lights, count=len(lights))


@router.post("/discover", response_model=DiscoveryResponse)
async def discover_lights(timeout: float = 5.0, broadcast: str = "255.255.255.255"):
    """Discover WiZ lights on the network."""
    discovery = LightDiscovery(broadcast_address=broadcast)
    new_lights = await discovery.discover_and_save(timeout)
    
    config = load_config()
    
    discovered = [
        LightResponse(ip=light.ip, mac=light.mac, name=light.name)
        for light in new_lights
    ]
    
    return DiscoveryResponse(
        discovered=discovered,
        new_count=len(new_lights),
        total_count=len(config.lights),
    )


@router.get("/{light_id}", response_model=LightResponse)
async def get_light(light_id: str):
    """Get status of a specific light."""
    try:
        controller = LightController.from_name(light_id)
        status = await controller.get_status()
        
        return LightResponse(
            ip=status.ip,
            name=status.name,
            mac=status.mac,
            state=status.state.value,
            brightness=status.brightness,
            brightness_percent=round(status.brightness / 255 * 100) if status.brightness else None,
            temperature=status.temperature,
            rgb=list(status.rgb) if status.rgb else None,
            scene=status.scene,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/{light_id}/on", response_model=SuccessResponse)
async def turn_on(light_id: str, brightness: Optional[int] = None):
    """Turn on a light."""
    try:
        controller = LightController.from_name(light_id)
        # Convert percentage to 0-255
        if brightness is not None:
            brightness = int(brightness * 255 / 100)
        await controller.turn_on(brightness)
        return SuccessResponse(success=True, message=f"Light {light_id} turned on")
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/{light_id}/off", response_model=SuccessResponse)
async def turn_off(light_id: str):
    """Turn off a light."""
    try:
        controller = LightController.from_name(light_id)
        await controller.turn_off()
        return SuccessResponse(success=True, message=f"Light {light_id} turned off")
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/{light_id}/toggle", response_model=SuccessResponse)
async def toggle(light_id: str):
    """Toggle a light on/off."""
    try:
        controller = LightController.from_name(light_id)
        new_state = await controller.toggle()
        return SuccessResponse(
            success=True, 
            message=f"Light {light_id} toggled to {new_state.value}"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.put("/{light_id}/brightness", response_model=SuccessResponse)
async def set_brightness(light_id: str, request: BrightnessRequest):
    """Set light brightness."""
    try:
        controller = LightController.from_name(light_id)
        await controller.set_brightness(request.value)
        return SuccessResponse(
            success=True, 
            message=f"Light {light_id} brightness set to {request.value}%"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.put("/{light_id}/color", response_model=SuccessResponse)
async def set_color(light_id: str, request: ColorRequest):
    """Set light color (RGB)."""
    try:
        controller = LightController.from_name(light_id)
        brightness = int(request.brightness * 255 / 100) if request.brightness else None
        await controller.set_color(request.r, request.g, request.b, brightness)
        return SuccessResponse(
            success=True,
            message=f"Light {light_id} color set to RGB({request.r}, {request.g}, {request.b})"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.put("/{light_id}/temperature", response_model=SuccessResponse)
async def set_temperature(light_id: str, request: TemperatureRequest):
    """Set light color temperature."""
    try:
        controller = LightController.from_name(light_id)
        brightness = int(request.brightness * 255 / 100) if request.brightness else None
        await controller.set_temperature(request.kelvin, brightness)
        return SuccessResponse(
            success=True,
            message=f"Light {light_id} temperature set to {request.kelvin}K"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/{light_id}/scene", response_model=SuccessResponse)
async def apply_scene(light_id: str, request: SceneRequest):
    """Apply a scene to a light."""
    try:
        controller = LightController.from_name(light_id)
        await SceneManager.apply_scene(controller.ip, request.scene)
        return SuccessResponse(
            success=True,
            message=f"Scene '{request.scene}' applied to {light_id}"
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ConnectionError as e:
        raise HTTPException(status_code=503, detail=str(e))
