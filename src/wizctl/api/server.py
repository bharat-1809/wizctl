"""FastAPI server for WiZ light control."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from wizctl import __version__
from wizctl.api.routes import groups, lights, scenes


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(
    title="wizctl API",
    description="""
REST API for controlling Philips WiZ smart lights.

- Discover lights on your network
- Control individual lights or groups
- Apply built-in or custom scenes
    """,
    version=__version__,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(lights.router)
app.include_router(scenes.router)
app.include_router(groups.router)


@app.get("/")
async def root():
    return {
        "name": "wizctl",
        "version": __version__,
        "status": "ok",
        "docs": "/docs",
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


def run_server(host: str = "0.0.0.0", port: int = 8000, reload: bool = False):
    import uvicorn
    uvicorn.run("wizctl.api.server:app", host=host, port=port, reload=reload)


if __name__ == "__main__":
    run_server()
