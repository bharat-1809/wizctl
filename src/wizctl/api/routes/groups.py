"""Group routes."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException

from wizctl.api.models import (
    BrightnessRequest,
    ColorRequest,
    GroupListResponse,
    GroupResponse,
    GroupStatusResponse,
    LightResponse,
    SceneRequest,
    SuccessResponse,
    TemperatureRequest,
)
from wizctl.core.groups import GroupManager

router = APIRouter(prefix="/groups", tags=["groups"])


@router.get("", response_model=GroupListResponse)
async def list_groups():
    groups_dict = GroupManager.get_groups()
    groups = [
        GroupResponse(
            name=name,
            light_names=lights if "*" not in lights else ["(all)"],
            light_count=len(GroupManager.get_group_lights(name)),
        )
        for name, lights in groups_dict.items()
    ]
    return GroupListResponse(groups=groups, count=len(groups))


@router.get("/{group_name}", response_model=GroupStatusResponse)
async def get_group_status(group_name: str):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    status = await GroupManager.get_group_status(group_name)
    return GroupStatusResponse(
        name=status.name,
        lights=[
            LightResponse(
                ip=light.ip,
                name=light.name,
                mac=light.mac,
                state=light.state.value,
                brightness=light.brightness,
                brightness_percent=round(light.brightness / 255 * 100) if light.brightness else None,
                temperature=light.temperature,
                rgb=list(light.rgb) if light.rgb else None,
                scene=light.scene,
            )
            for light in status.lights
        ],
        all_on=status.all_on,
        all_off=status.all_off,
        light_count=len(status.lights),
    )


@router.post("/{group_name}/on", response_model=SuccessResponse)
async def turn_on_group(group_name: str, brightness: Optional[int] = None):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    if brightness is not None:
        brightness = int(brightness * 255 / 100)

    count = await GroupManager.turn_on_group(group_name, brightness)
    return SuccessResponse(success=True, message=f"Turned on {count} lights")


@router.post("/{group_name}/off", response_model=SuccessResponse)
async def turn_off_group(group_name: str):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    count = await GroupManager.turn_off_group(group_name)
    return SuccessResponse(success=True, message=f"Turned off {count} lights")


@router.post("/{group_name}/toggle", response_model=SuccessResponse)
async def toggle_group(group_name: str):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    new_state = await GroupManager.toggle_group(group_name)
    return SuccessResponse(success=True, message=f"Toggled to {new_state.value}")


@router.put("/{group_name}/brightness", response_model=SuccessResponse)
async def set_group_brightness(group_name: str, request: BrightnessRequest):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    count = await GroupManager.set_group_brightness(group_name, request.value)
    return SuccessResponse(success=True, message=f"Set brightness for {count} lights")


@router.put("/{group_name}/color", response_model=SuccessResponse)
async def set_group_color(group_name: str, request: ColorRequest):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    brightness = int(request.brightness * 255 / 100) if request.brightness else None
    count = await GroupManager.set_group_color(group_name, request.r, request.g, request.b, brightness)
    return SuccessResponse(success=True, message=f"Set color for {count} lights")


@router.put("/{group_name}/temperature", response_model=SuccessResponse)
async def set_group_temperature(group_name: str, request: TemperatureRequest):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    brightness = int(request.brightness * 255 / 100) if request.brightness else None
    count = await GroupManager.set_group_temperature(group_name, request.kelvin, brightness)
    return SuccessResponse(success=True, message=f"Set temperature for {count} lights")


@router.post("/{group_name}/scene", response_model=SuccessResponse)
async def apply_scene_to_group(group_name: str, request: SceneRequest):
    groups = GroupManager.get_groups()
    if group_name not in groups:
        raise HTTPException(status_code=404, detail=f"Group not found: {group_name}")

    count = await GroupManager.apply_scene_to_group(group_name, request.scene)
    return SuccessResponse(success=True, message=f"Applied scene to {count} lights")
