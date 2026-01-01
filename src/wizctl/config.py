"""Configuration management."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml
from pydantic import BaseModel


class LightConfig(BaseModel):
    ip: str
    alias: Optional[str] = None
    mac: Optional[str] = None


class SceneConfig(BaseModel):
    brightness: Optional[int] = None
    temperature: Optional[int] = None
    color: Optional[List[int]] = None


class Config(BaseModel):
    lights: Dict[str, LightConfig] = {}
    groups: Dict[str, List[str]] = {"all": ["*"]}
    scenes: Dict[str, SceneConfig] = {}


def get_config_path() -> Path:
    """Get the configuration file path."""
    env_path = os.environ.get("WIZCTL_CONFIG")
    if env_path:
        return Path(env_path)

    local_config = Path("config/lights.yaml")
    if local_config.exists():
        return local_config

    package_config = Path(__file__).parent.parent.parent / "config" / "lights.yaml"
    if package_config.exists():
        return package_config

    home_config = Path.home() / ".config" / "wizctl" / "lights.yaml"
    home_config.parent.mkdir(parents=True, exist_ok=True)
    return home_config


def load_config() -> Config:
    """Load configuration from YAML file."""
    config_path = get_config_path()

    if not config_path.exists():
        default_config = Config()
        save_config(default_config)
        return default_config

    with open(config_path) as f:
        data = yaml.safe_load(f) or {}

    lights = {}
    for name, light_data in data.get("lights", {}).items():
        if isinstance(light_data, dict):
            lights[name] = LightConfig(**light_data)

    scenes = {}
    for name, scene_data in data.get("scenes", {}).items():
        if isinstance(scene_data, dict):
            scenes[name] = SceneConfig(**scene_data)

    return Config(
        lights=lights,
        groups=data.get("groups", {"all": ["*"]}),
        scenes=scenes,
    )


def save_config(config: Config) -> None:
    """Save configuration to YAML file."""
    config_path = get_config_path()
    config_path.parent.mkdir(parents=True, exist_ok=True)

    data: Dict[str, Any] = {
        "lights": {name: light.model_dump(exclude_none=True) for name, light in config.lights.items()},
        "groups": config.groups,
        "scenes": {name: scene.model_dump(exclude_none=True) for name, scene in config.scenes.items()},
    }

    with open(config_path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)


def get_light_by_name(name: str, config: Optional[Config] = None) -> Optional[LightConfig]:
    """Get a light by name, alias, or IP."""
    if config is None:
        config = load_config()

    if name in config.lights:
        return config.lights[name]

    for light_name, light in config.lights.items():
        if light.alias and light.alias.lower() == name.lower():
            return light

    for light in config.lights.values():
        if light.ip == name:
            return light

    return None


def get_lights_in_group(group_name: str, config: Optional[Config] = None) -> List[LightConfig]:
    """Get all lights in a group."""
    if config is None:
        config = load_config()

    if group_name not in config.groups:
        return []

    group = config.groups[group_name]
    if "*" in group:
        return list(config.lights.values())

    lights = []
    for name in group:
        light = get_light_by_name(name, config)
        if light:
            lights.append(light)

    return lights
