"""wizctl CLI."""

from __future__ import annotations

import asyncio
from typing import Optional, Callable, Any

import typer
from rich.console import Console
from rich.table import Table

from wizctl import __version__
from wizctl.config import load_config, save_config
from wizctl.core.discovery import LightDiscovery
from wizctl.core.light import LightController, LightState
from wizctl.core.scenes import SceneManager
from wizctl.core.groups import GroupManager


def run_async(coro) -> Any:
    return asyncio.run(coro)


async def run_with_controller(light: str, action: Callable) -> Any:
    controller = LightController.from_name(light)
    try:
        return await action(controller)
    finally:
        await controller.close()


app = typer.Typer(name="wizctl", help="Control Philips WiZ smart lights.", no_args_is_help=True)
console = Console()


def version_callback(value: bool):
    if value:
        console.print(f"wizctl {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: bool = typer.Option(None, "--version", "-v", callback=version_callback, is_eager=True),
):
    pass


@app.command()
def discover(
    timeout: float = typer.Option(5.0, "--timeout", "-t"),
    broadcast: str = typer.Option("255.255.255.255", "--broadcast", "-b"),
):
    """Discover lights on the network."""
    console.print("Discovering lights...")
    discovery = LightDiscovery(broadcast_address=broadcast)
    new_lights = asyncio.run(discovery.discover_and_save(timeout))

    if new_lights:
        console.print(f"[green]Found {len(new_lights)} new light(s)[/green]")
        for light in new_lights:
            console.print(f"  {light.ip} ({light.mac})")
    else:
        console.print("[yellow]No new lights found[/yellow]")

    config = load_config()
    console.print(f"[dim]Total: {len(config.lights)} lights[/dim]")


@app.command(name="list")
def list_lights():
    """List configured lights."""
    config = load_config()
    if not config.lights:
        console.print("[yellow]No lights. Run 'wizctl discover' first.[/yellow]")
        return

    table = Table(title="Lights")
    table.add_column("Name", style="cyan")
    table.add_column("Alias", style="green")
    table.add_column("IP", style="yellow")
    table.add_column("MAC", style="dim")

    for name, light in config.lights.items():
        table.add_row(name, light.alias or "-", light.ip, light.mac or "-")
    console.print(table)


@app.command()
def status(light: str = typer.Argument(...)):
    """Get light status."""
    try:
        s = run_async(run_with_controller(light, lambda c: c.get_status()))
        table = Table(title=f"Status: {light}")
        table.add_column("Property", style="cyan")
        table.add_column("Value", style="green")
        table.add_row("IP", s.ip)
        table.add_row("Name", s.name or "-")
        table.add_row("State", "ON" if s.state == LightState.ON else "OFF")
        if s.brightness is not None:
            table.add_row("Brightness", f"{round(s.brightness / 255 * 100)}%")
        if s.temperature:
            table.add_row("Temperature", f"{s.temperature}K")
        if s.rgb:
            table.add_row("Color", f"RGB({s.rgb[0]}, {s.rgb[1]}, {s.rgb[2]})")
        if s.scene:
            table.add_row("Scene", s.scene)
        console.print(table)
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def on(
    light: str = typer.Argument(...),
    brightness: Optional[int] = typer.Option(None, "--brightness", "-b"),
):
    """Turn on a light."""
    try:
        b = int(brightness * 255 / 100) if brightness is not None else None
        run_async(run_with_controller(light, lambda c: c.turn_on(b)))
        console.print(f"[green]{light} on[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def off(light: str = typer.Argument(...)):
    """Turn off a light."""
    try:
        run_async(run_with_controller(light, lambda c: c.turn_off()))
        console.print(f"[green]{light} off[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def toggle(light: str = typer.Argument(...)):
    """Toggle a light."""
    try:
        new_state = run_async(run_with_controller(light, lambda c: c.toggle()))
        console.print(f"[green]{light} {'on' if new_state == LightState.ON else 'off'}[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def brightness(light: str = typer.Argument(...), value: int = typer.Argument(...)):
    """Set brightness (0-100)."""
    try:
        run_async(run_with_controller(light, lambda c: c.set_brightness(value)))
        console.print(f"[green]{light} brightness {value}%[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def color(
    light: str = typer.Argument(...),
    r: int = typer.Argument(...),
    g: int = typer.Argument(...),
    b: int = typer.Argument(...),
    brightness_opt: Optional[int] = typer.Option(None, "--brightness", "-b"),
):
    """Set RGB color."""
    try:
        bv = int(brightness_opt * 255 / 100) if brightness_opt else None
        run_async(run_with_controller(light, lambda c: c.set_color(r, g, b, bv)))
        console.print(f"[green]{light} color RGB({r}, {g}, {b})[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def temp(
    light: str = typer.Argument(...),
    kelvin: int = typer.Argument(...),
    brightness_opt: Optional[int] = typer.Option(None, "--brightness", "-b"),
):
    """Set color temperature (2200-6500K)."""
    try:
        bv = int(brightness_opt * 255 / 100) if brightness_opt else None
        run_async(run_with_controller(light, lambda c: c.set_temperature(kelvin, bv)))
        console.print(f"[green]{light} temp {kelvin}K[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def scene(light: str = typer.Argument(...), scene_name: str = typer.Argument(...)):
    """Apply a scene."""
    try:
        SceneManager.apply_scene_sync(light, scene_name)
        console.print(f"[green]{light} scene '{scene_name}'[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def scenes():
    """List available scenes."""
    builtin = SceneManager.get_builtin_scenes()
    custom = SceneManager.get_custom_scenes()

    console.print("[bold]Built-in:[/bold]")
    for i, name in enumerate(builtin, 1):
        console.print(f"  {i:2}. {name}")

    if custom:
        console.print("\n[bold]Custom:[/bold]")
        for name, s in custom.items():
            parts = []
            if s.brightness:
                parts.append(f"{s.brightness}%")
            if s.temperature:
                parts.append(f"{s.temperature}K")
            if s.color:
                parts.append(f"RGB{s.color}")
            console.print(f"  - {name}: {', '.join(parts)}")


group_app = typer.Typer(help="Group commands")
app.add_typer(group_app, name="group")


@group_app.command(name="list")
def list_groups():
    """List groups."""
    groups = GroupManager.get_groups()
    table = Table(title="Groups")
    table.add_column("Name", style="cyan")
    table.add_column("Lights", style="green")
    table.add_column("Count", style="yellow")

    for name, lights in groups.items():
        count = len(GroupManager.get_group_lights(name))
        lights_str = ", ".join(lights) if "*" not in lights else "(all)"
        table.add_row(name, lights_str, str(count))
    console.print(table)


@group_app.command()
def on(
    group_name: str = typer.Argument(...),
    brightness_opt: Optional[int] = typer.Option(None, "--brightness", "-b"),
):
    """Turn on group."""
    try:
        bv = int(brightness_opt * 255 / 100) if brightness_opt else None
        count = asyncio.run(GroupManager.turn_on_group(group_name, bv))
        console.print(f"[green]{count} lights on[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@group_app.command()
def off(group_name: str = typer.Argument(...)):
    """Turn off group."""
    try:
        count = asyncio.run(GroupManager.turn_off_group(group_name))
        console.print(f"[green]{count} lights off[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@group_app.command()
def toggle(group_name: str = typer.Argument(...)):
    """Toggle group."""
    try:
        new_state = asyncio.run(GroupManager.toggle_group(group_name))
        console.print(f"[green]Group {'on' if new_state == LightState.ON else 'off'}[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@group_app.command()
def scene(group_name: str = typer.Argument(...), scene_name: str = typer.Argument(...)):
    """Apply scene to group."""
    try:
        count = asyncio.run(GroupManager.apply_scene_to_group(group_name, scene_name))
        console.print(f"[green]Scene applied to {count} lights[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def alias(light: str = typer.Argument(...), new_alias: str = typer.Argument(...)):
    """Set a light alias."""
    config = load_config()
    found = False
    for name, cfg in config.lights.items():
        if name == light or cfg.ip == light:
            config.lights[name].alias = new_alias
            found = True
            break

    if not found:
        console.print(f"[red]Light not found: {light}[/red]")
        raise typer.Exit(1)

    save_config(config)
    console.print(f"[green]Alias: {light} -> {new_alias}[/green]")


@app.command()
def serve(
    host: str = typer.Option("0.0.0.0", "--host", "-h"),
    port: int = typer.Option(8000, "--port", "-p"),
    reload: bool = typer.Option(False, "--reload", "-r"),
):
    """Start the API server."""
    console.print(f"Starting server on {host}:{port}")
    console.print(f"Docs: http://localhost:{port}/docs\n")
    from wizctl.api.server import run_server
    run_server(host=host, port=port, reload=reload)


if __name__ == "__main__":
    app()
