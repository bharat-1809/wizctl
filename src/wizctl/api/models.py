"""Pydantic models for API requests and responses."""

from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field


# Request models

class BrightnessRequest(BaseModel):
    """Request to set brightness."""

    value: int = Field(..., ge=0, le=100, description="Brightness percentage (0-100)")


class ColorRequest(BaseModel):
    """Request to set RGB color."""

    r: int = Field(..., ge=0, le=255, description="Red value (0-255)")
    g: int = Field(..., ge=0, le=255, description="Green value (0-255)")
    b: int = Field(..., ge=0, le=255, description="Blue value (0-255)")
    brightness: Optional[int] = Field(None, ge=0, le=100, description="Optional brightness (0-100)")


class TemperatureRequest(BaseModel):
    """Request to set color temperature."""

    kelvin: int = Field(..., ge=2200, le=6500, description="Color temperature in Kelvin")
    brightness: Optional[int] = Field(None, ge=0, le=100, description="Optional brightness (0-100)")


class SceneRequest(BaseModel):
    """Request to apply a scene."""

    scene: str = Field(..., description="Scene name")


# Response models

class LightResponse(BaseModel):
    """Response with light information."""

    ip: str
    name: Optional[str] = None
    alias: Optional[str] = None
    mac: Optional[str] = None
    state: Optional[str] = None
    brightness: Optional[int] = None
    brightness_percent: Optional[int] = None
    temperature: Optional[int] = None
    rgb: Optional[List[int]] = None
    scene: Optional[str] = None


class LightListResponse(BaseModel):
    """Response with list of lights."""

    lights: List[LightResponse]
    count: int


class DiscoveryResponse(BaseModel):
    """Response from light discovery."""

    discovered: List[LightResponse]
    new_count: int
    total_count: int


class GroupResponse(BaseModel):
    """Response with group information."""

    name: str
    light_names: List[str]
    light_count: int


class GroupListResponse(BaseModel):
    """Response with list of groups."""

    groups: List[GroupResponse]
    count: int


class GroupStatusResponse(BaseModel):
    """Response with group status."""

    name: str
    lights: List[LightResponse]
    all_on: bool
    all_off: bool
    light_count: int


class SceneListResponse(BaseModel):
    """Response with list of scenes."""

    builtin: List[str]
    custom: List[str]


class SuccessResponse(BaseModel):
    """Generic success response."""

    success: bool
    message: str


class ErrorResponse(BaseModel):
    """Error response."""

    error: str
    detail: Optional[str] = None
