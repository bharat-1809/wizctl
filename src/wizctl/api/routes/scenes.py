"""Scene API routes."""

from fastapi import APIRouter

from wizctl.api.models import SceneListResponse
from wizctl.core.scenes import SceneManager

router = APIRouter(prefix="/scenes", tags=["scenes"])


@router.get("", response_model=SceneListResponse)
async def list_scenes():
    """List all available scenes (built-in and custom)."""
    builtin = SceneManager.get_builtin_scenes()
    custom = list(SceneManager.get_custom_scenes().keys())
    
    return SceneListResponse(builtin=builtin, custom=custom)


@router.get("/builtin")
async def list_builtin_scenes():
    """List all built-in WiZ scenes."""
    return {"scenes": SceneManager.get_builtin_scenes()}


@router.get("/custom")
async def list_custom_scenes():
    """List all custom scenes from configuration."""
    scenes = SceneManager.get_custom_scenes()
    return {
        "scenes": [
            {
                "name": name,
                "brightness": scene.brightness,
                "temperature": scene.temperature,
                "color": list(scene.color) if scene.color else None,
            }
            for name, scene in scenes.items()
        ]
    }

