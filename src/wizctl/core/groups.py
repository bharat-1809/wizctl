"""Group management."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple, Any

from wizctl.config import load_config, get_lights_in_group, LightConfig
from wizctl.core.light import LightController, LightState, LightStatus


@dataclass
class GroupStatus:
    name: str
    lights: List[LightStatus]
    all_on: bool
    all_off: bool

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "lights": [light.to_dict() for light in self.lights],
            "all_on": self.all_on,
            "all_off": self.all_off,
            "light_count": len(self.lights),
        }


async def _run_with_cleanup(light_ip: str, action) -> Tuple[bool, Any]:
    controller = LightController(light_ip)
    try:
        result = await action(controller)
        return (True, result)
    except Exception:
        return (False, None)
    finally:
        await controller.close()


class GroupManager:
    @staticmethod
    def get_groups() -> Dict[str, List[str]]:
        return load_config().groups

    @staticmethod
    def get_group_lights(group_name: str) -> List[LightConfig]:
        return get_lights_in_group(group_name)

    @classmethod
    async def get_group_status(cls, group_name: str) -> GroupStatus:
        lights = cls.get_group_lights(group_name)
        if not lights:
            return GroupStatus(name=group_name, lights=[], all_on=False, all_off=True)

        results = await asyncio.gather(*[
            _run_with_cleanup(light.ip, lambda c: c.get_status())
            for light in lights
        ])

        valid_statuses = [r[1] for r in results if r[0] and r[1] is not None]
        all_on = all(s.state == LightState.ON for s in valid_statuses) if valid_statuses else False
        all_off = all(s.state == LightState.OFF for s in valid_statuses) if valid_statuses else True

        return GroupStatus(name=group_name, lights=valid_statuses, all_on=all_on, all_off=all_off)

    @classmethod
    async def turn_on_group(cls, group_name: str, brightness: Optional[int] = None) -> int:
        lights = cls.get_group_lights(group_name)
        results = await asyncio.gather(*[
            _run_with_cleanup(light.ip, lambda c: c.turn_on(brightness))
            for light in lights
        ])
        return sum(1 for r in results if r[0])

    @classmethod
    async def turn_off_group(cls, group_name: str) -> int:
        lights = cls.get_group_lights(group_name)
        results = await asyncio.gather(*[
            _run_with_cleanup(light.ip, lambda c: c.turn_off())
            for light in lights
        ])
        return sum(1 for r in results if r[0])

    @classmethod
    async def toggle_group(cls, group_name: str) -> LightState:
        status = await cls.get_group_status(group_name)
        if status.all_off:
            await cls.turn_on_group(group_name)
            return LightState.ON
        else:
            await cls.turn_off_group(group_name)
            return LightState.OFF

    @classmethod
    async def set_group_brightness(cls, group_name: str, brightness: int) -> int:
        lights = cls.get_group_lights(group_name)
        results = await asyncio.gather(*[
            _run_with_cleanup(light.ip, lambda c: c.set_brightness(brightness))
            for light in lights
        ])
        return sum(1 for r in results if r[0])

    @classmethod
    async def set_group_color(
        cls, group_name: str, r: int, g: int, b: int, brightness: Optional[int] = None
    ) -> int:
        lights = cls.get_group_lights(group_name)
        results = await asyncio.gather(*[
            _run_with_cleanup(light.ip, lambda c: c.set_color(r, g, b, brightness))
            for light in lights
        ])
        return sum(1 for r in results if r[0])

    @classmethod
    async def set_group_temperature(
        cls, group_name: str, kelvin: int, brightness: Optional[int] = None
    ) -> int:
        lights = cls.get_group_lights(group_name)
        results = await asyncio.gather(*[
            _run_with_cleanup(light.ip, lambda c: c.set_temperature(kelvin, brightness))
            for light in lights
        ])
        return sum(1 for r in results if r[0])

    @classmethod
    async def apply_scene_to_group(cls, group_name: str, scene_name: str) -> int:
        from wizctl.core.scenes import SceneManager
        lights = cls.get_group_lights(group_name)

        async def apply_scene(light_ip: str) -> bool:
            try:
                return await SceneManager.apply_scene(light_ip, scene_name)
            except Exception:
                return False

        results = await asyncio.gather(*[apply_scene(light.ip) for light in lights])
        return sum(1 for r in results if r)


def get_group_status_sync(group_name: str) -> GroupStatus:
    return asyncio.run(GroupManager.get_group_status(group_name))


def turn_on_group_sync(group_name: str, brightness: Optional[int] = None) -> int:
    return asyncio.run(GroupManager.turn_on_group(group_name, brightness))


def turn_off_group_sync(group_name: str) -> int:
    return asyncio.run(GroupManager.turn_off_group(group_name))


def toggle_group_sync(group_name: str) -> LightState:
    return asyncio.run(GroupManager.toggle_group(group_name))
