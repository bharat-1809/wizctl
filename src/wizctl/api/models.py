"""API models."""

from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field


class BrightnessRequest(BaseModel):
    value: int = Field(..., ge=0, le=100)


class ColorRequest(BaseModel):
    r: int = Field(..., ge=0, le=255)
    g: int = Field(..., ge=0, le=255)
    b: int = Field(..., ge=0, le=255)
    brightness: Optional[int] = Field(None, ge=0, le=100)


class TemperatureRequest(BaseModel):
    kelvin: int = Field(..., ge=2200, le=6500)
    brightness: Optional[int] = Field(None, ge=0, le=100)


class SceneRequest(BaseModel):
    scene: str


class LightResponse(BaseModel):
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
    lights: List[LightResponse]
    count: int


class DiscoveryResponse(BaseModel):
    discovered: List[LightResponse]
    new_count: int
    total_count: int


class GroupResponse(BaseModel):
    name: str
    light_names: List[str]
    light_count: int


class GroupListResponse(BaseModel):
    groups: List[GroupResponse]
    count: int


class GroupStatusResponse(BaseModel):
    name: str
    lights: List[LightResponse]
    all_on: bool
    all_off: bool
    light_count: int


class SceneListResponse(BaseModel):
    builtin: List[str]
    custom: List[str]


class SuccessResponse(BaseModel):
    success: bool
    message: str


class ErrorResponse(BaseModel):
    error: str
    detail: Optional[str] = None
