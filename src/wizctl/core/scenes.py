"""Scene management."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from enum import IntEnum
from typing import Dict, List, Optional, Tuple

from wizctl.config import load_config
from wizctl.core.light import LightController


class WizScene(IntEnum):
    OCEAN = 1
    ROMANCE = 2
    SUNSET = 3
    PARTY = 4
    FIREPLACE = 5
    COZY = 6
    FOREST = 7
    PASTEL_COLORS = 8
    WAKE_UP = 9
    BEDTIME = 10
    WARM_WHITE = 11
    DAYLIGHT = 12
    COOL_WHITE = 13
    NIGHT_LIGHT = 14
    FOCUS = 15
    RELAX = 16
    TRUE_COLORS = 17
    TV_TIME = 18
    PLANT_GROWTH = 19
    SPRING = 20
    SUMMER = 21
    FALL = 22
    DEEP_DIVE = 23
    JUNGLE = 24
    MOJITO = 25
    CLUB = 26
    CHRISTMAS = 27
    HALLOWEEN = 28
    CANDLELIGHT = 29
    GOLDEN_WHITE = 30
    PULSE = 31
    STEAMPUNK = 32


@dataclass
class Scene:
    name: str
    brightness: Optional[int] = None
    temperature: Optional[int] = None
    color: Optional[Tuple[int, int, int]] = None
    wiz_scene_id: Optional[int] = None

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "brightness": self.brightness,
            "temperature": self.temperature,
            "color": list(self.color) if self.color else None,
            "wiz_scene_id": self.wiz_scene_id,
        }


class SceneManager:
    BUILTIN_SCENES = {scene.name.lower().replace("_", " "): scene.value for scene in WizScene}

    @classmethod
    def get_builtin_scenes(cls) -> List[str]:
        return [scene.name.replace("_", " ").title() for scene in WizScene]

    @classmethod
    def get_custom_scenes(cls) -> Dict[str, Scene]:
        config = load_config()
        scenes = {}
        for name, scene_config in config.scenes.items():
            color = None
            if scene_config.color and len(scene_config.color) == 3:
                color = tuple(scene_config.color)  # type: ignore
            scenes[name] = Scene(
                name=name,
                brightness=scene_config.brightness,
                temperature=scene_config.temperature,
                color=color,
            )
        return scenes

    @classmethod
    def get_scene(cls, name: str) -> Optional[Scene]:
        """Get a scene by name (custom or built-in)."""
        custom = cls.get_custom_scenes()
        for key, scene in custom.items():
            if key.lower() == name.lower():
                return scene

        name_normalized = name.lower().replace("_", " ").replace("-", " ")
        if name_normalized in cls.BUILTIN_SCENES:
            return Scene(name=name, wiz_scene_id=cls.BUILTIN_SCENES[name_normalized])

        for scene_name, scene_id in cls.BUILTIN_SCENES.items():
            if name_normalized in scene_name or scene_name in name_normalized:
                return Scene(name=scene_name.title(), wiz_scene_id=scene_id)

        return None

    @classmethod
    async def apply_scene(cls, light_ip: str, scene_name: str) -> bool:
        """Apply a scene to a light."""
        scene = cls.get_scene(scene_name)
        if not scene:
            raise ValueError(f"Scene not found: {scene_name}")

        controller = LightController(light_ip)
        try:
            if scene.wiz_scene_id:
                return await controller.set_scene(scene.wiz_scene_id)

            if scene.color:
                await controller.set_color(
                    scene.color[0], scene.color[1], scene.color[2],
                    brightness=scene.brightness,
                )
            elif scene.temperature:
                await controller.set_temperature(scene.temperature, brightness=scene.brightness)
            elif scene.brightness:
                await controller.set_brightness(scene.brightness)

            return True
        finally:
            await controller.close()

    @classmethod
    def apply_scene_sync(cls, light_name_or_ip: str, scene_name: str) -> bool:
        from wizctl.config import get_light_by_name
        light = get_light_by_name(light_name_or_ip)
        ip = light.ip if light else light_name_or_ip
        return asyncio.run(cls.apply_scene(ip, scene_name))
