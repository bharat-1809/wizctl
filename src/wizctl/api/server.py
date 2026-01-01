"""FastAPI server for WiZ light control."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from wizctl import __version__
from wizctl.api.routes import groups, lights, scenes


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    yield
    # Shutdown


app = FastAPI(
    title="WiZ Light Controller API",
    description="""
Control Philips WiZ smart lights via REST API.

## Features

- **Light Discovery**: Auto-discover WiZ lights on your network
- **Individual Control**: On/off, brightness, color, temperature
- **Group Control**: Control multiple lights at once
- **Scenes**: Apply built-in WiZ scenes or custom scenes

## Usage

1. First, discover lights: `POST /lights/discover`
2. List discovered lights: `GET /lights`
3. Control lights: `POST /lights/{id}/on`, `PUT /lights/{id}/brightness`, etc.

## AI Agent Integration

This API is designed for programmatic control. Use the OpenAPI schema at `/openapi.json`
to understand available operations.
    """,
    version=__version__,
    lifespan=lifespan,
)

# Add CORS middleware for web UI access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure this for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(lights.router)
app.include_router(scenes.router)
app.include_router(groups.router)


@app.get("/")
async def root():
    """API root - health check and info."""
    return {
        "name": "WiZ Light Controller",
        "version": __version__,
        "status": "running",
        "docs": "/docs",
        "openapi": "/openapi.json",
    }


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}


def run_server(host: str = "0.0.0.0", port: int = 8000, reload: bool = False):
    """Run the API server.
    
    Args:
        host: Host to bind to.
        port: Port to bind to.
        reload: Enable auto-reload for development.
    """
    import uvicorn
    
    uvicorn.run(
        "wizctl.api.server:app",
        host=host,
        port=port,
        reload=reload,
    )


if __name__ == "__main__":
    run_server()

