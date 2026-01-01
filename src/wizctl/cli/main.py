"""CLI for WiZ Light Controller."""

from __future__ import annotations

import asyncio
from typing import Optional, TypeVar, Callable, Any

import typer
from rich.console import Console
from rich.table import Table

from wizctl import __version__
from wizctl.config import load_config, save_config, LightConfig
from wizctl.core.discovery import LightDiscovery
from wizctl.core.light import LightController, LightState
from wizctl.core.scenes import SceneManager
from wizctl.core.groups import GroupManager

T = TypeVar('T')


def run_async(coro) -> Any:
    """Run an async coroutine with proper cleanup to avoid event loop errors."""
    return asyncio.run(coro)


async def run_with_controller(light: str, action: Callable) -> Any:
    """Run an action with a controller and ensure cleanup."""
    controller = LightController.from_name(light)
    try:
        return await action(controller)
    finally:
        await controller.close()


app = typer.Typer(
    name="wizctl",
    help="Control Philips WiZ smart lights from the command line.",
    no_args_is_help=True,
)

console = Console()


def version_callback(value: bool):
    if value:
        console.print(f"wizctl version {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: bool = typer.Option(
        None, "--version", "-v", callback=version_callback, is_eager=True,
        help="Show version and exit."
    ),
):
    """WiZ Light Controller - Control your smart lights from the terminal."""
    pass


# ============================================================================
# Discovery Commands
# ============================================================================

@app.command()
def discover(
    timeout: float = typer.Option(5.0, "--timeout", "-t", help="Discovery timeout in seconds"),
    broadcast: str = typer.Option("255.255.255.255", "--broadcast", "-b", help="Broadcast address"),
):
    """Discover WiZ lights on the network."""
    console.print("[bold blue]Discovering WiZ lights...[/bold blue]")
    
    discovery = LightDiscovery(broadcast_address=broadcast)
    new_lights = asyncio.run(discovery.discover_and_save(timeout))
    
    if new_lights:
        console.print(f"[green]Found {len(new_lights)} new light(s)![/green]")
        for light in new_lights:
            console.print(f"  • {light.ip} (MAC: {light.mac})")
    else:
        console.print("[yellow]No new lights found.[/yellow]")
    
    config = load_config()
    console.print(f"\n[dim]Total lights in config: {len(config.lights)}[/dim]")


@app.command(name="list")
def list_lights():
    """List all configured lights."""
    config = load_config()
    
    if not config.lights:
        console.print("[yellow]No lights configured. Run 'wizctl discover' first.[/yellow]")
        return
    
    table = Table(title="Configured Lights")
    table.add_column("Name", style="cyan")
    table.add_column("Alias", style="green")
    table.add_column("IP Address", style="yellow")
    table.add_column("MAC", style="dim")
    
    for name, light in config.lights.items():
        table.add_row(name, light.alias or "-", light.ip, light.mac or "-")
    
    console.print(table)


@app.command()
def status(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
):
    """Get the current status of a light."""
    try:
        light_status = run_async(run_with_controller(light, lambda c: c.get_status()))
        
        table = Table(title=f"Light Status: {light}")
        table.add_column("Property", style="cyan")
        table.add_column("Value", style="green")
        
        table.add_row("IP", light_status.ip)
        table.add_row("Name", light_status.name or "-")
        table.add_row("State", "ON" if light_status.state == LightState.ON else "OFF")
        
        if light_status.brightness is not None:
            pct = round(light_status.brightness / 255 * 100)
            table.add_row("Brightness", f"{pct}% ({light_status.brightness}/255)")
        
        if light_status.temperature:
            table.add_row("Temperature", f"{light_status.temperature}K")
        
        if light_status.rgb:
            r, g, b = light_status.rgb
            table.add_row("Color (RGB)", f"({r}, {g}, {b})")
        
        if light_status.scene:
            table.add_row("Scene", light_status.scene)
        
        console.print(table)
        
    except ValueError as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)
    except ConnectionError as e:
        console.print(f"[red]Connection error: {e}[/red]")
        raise typer.Exit(1)


# ============================================================================
# Basic Light Control
# ============================================================================

@app.command()
def on(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
    brightness: Optional[int] = typer.Option(None, "--brightness", "-b", help="Brightness (0-100)"),
):
    """Turn on a light."""
    try:
        brightness_val = int(brightness * 255 / 100) if brightness is not None else None
        run_async(run_with_controller(light, lambda c: c.turn_on(brightness_val)))
        console.print(f"[green]Light '{light}' turned on[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def off(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
):
    """Turn off a light."""
    try:
        run_async(run_with_controller(light, lambda c: c.turn_off()))
        console.print(f"[green]Light '{light}' turned off[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def toggle(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
):
    """Toggle a light on/off."""
    try:
        new_state = run_async(run_with_controller(light, lambda c: c.toggle()))
        state_str = "on" if new_state == LightState.ON else "off"
        console.print(f"[green]Light '{light}' toggled {state_str}[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def brightness(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
    value: int = typer.Argument(..., help="Brightness (0-100)"),
):
    """Set light brightness."""
    try:
        run_async(run_with_controller(light, lambda c: c.set_brightness(value)))
        console.print(f"[green]Light '{light}' brightness set to {value}%[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def color(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
    r: int = typer.Argument(..., help="Red (0-255)"),
    g: int = typer.Argument(..., help="Green (0-255)"),
    b: int = typer.Argument(..., help="Blue (0-255)"),
    brightness_opt: Optional[int] = typer.Option(None, "--brightness", "-b", help="Brightness (0-100)"),
):
    """Set light color (RGB)."""
    try:
        brightness_val = int(brightness_opt * 255 / 100) if brightness_opt else None
        run_async(run_with_controller(light, lambda c: c.set_color(r, g, b, brightness_val)))
        console.print(f"[green]Light '{light}' color set to RGB({r}, {g}, {b})[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def temp(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
    kelvin: int = typer.Argument(..., help="Color temperature in Kelvin (2200-6500)"),
    brightness_opt: Optional[int] = typer.Option(None, "--brightness", "-b", help="Brightness (0-100)"),
):
    """Set light color temperature."""
    try:
        brightness_val = int(brightness_opt * 255 / 100) if brightness_opt else None
        run_async(run_with_controller(light, lambda c: c.set_temperature(kelvin, brightness_val)))
        console.print(f"[green]Light '{light}' temperature set to {kelvin}K[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


# ============================================================================
# Scene Commands
# ============================================================================

@app.command()
def scene(
    light: str = typer.Argument(..., help="Light name, alias, or IP address"),
    scene_name: str = typer.Argument(..., help="Scene name (built-in or custom)"),
):
    """Apply a scene to a light."""
    try:
        SceneManager.apply_scene_sync(light, scene_name)
        console.print(f"[green]Scene '{scene_name}' applied to '{light}'[/green]")
    except (ValueError, ConnectionError) as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def scenes():
    """List all available scenes."""
    builtin = SceneManager.get_builtin_scenes()
    custom = SceneManager.get_custom_scenes()
    
    console.print("[bold]Built-in WiZ Scenes:[/bold]")
    for i, name in enumerate(builtin, 1):
        console.print(f"  {i:2}. {name}")
    
    if custom:
        console.print("\n[bold]Custom Scenes:[/bold]")
        for name, scene_obj in custom.items():
            details = []
            if scene_obj.brightness:
                details.append(f"brightness={scene_obj.brightness}%")
            if scene_obj.temperature:
                details.append(f"temp={scene_obj.temperature}K")
            if scene_obj.color:
                details.append(f"color=RGB{scene_obj.color}")
            console.print(f"  - {name}: {', '.join(details)}")


# ============================================================================
# Group Commands
# ============================================================================

group_app = typer.Typer(help="Control groups of lights")
app.add_typer(group_app, name="group")


@group_app.command(name="list")
def list_groups():
    """List all configured groups."""
    groups = GroupManager.get_groups()
    
    table = Table(title="Light Groups")
    table.add_column("Group", style="cyan")
    table.add_column("Lights", style="green")
    table.add_column("Count", style="yellow")
    
    for name, lights in groups.items():
        light_count = len(GroupManager.get_group_lights(name))
        lights_str = ", ".join(lights) if "*" not in lights else "(all lights)"
        table.add_row(name, lights_str, str(light_count))
    
    console.print(table)


@group_app.command()
def on(
    group_name: str = typer.Argument(..., help="Group name"),
    brightness_opt: Optional[int] = typer.Option(None, "--brightness", "-b", help="Brightness (0-100)"),
):
    """Turn on all lights in a group."""
    try:
        brightness_val = int(brightness_opt * 255 / 100) if brightness_opt else None
        count = asyncio.run(GroupManager.turn_on_group(group_name, brightness_val))
        console.print(f"[green]Turned on {count} light(s) in group '{group_name}'[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@group_app.command()
def off(
    group_name: str = typer.Argument(..., help="Group name"),
):
    """Turn off all lights in a group."""
    try:
        count = asyncio.run(GroupManager.turn_off_group(group_name))
        console.print(f"[green]Turned off {count} light(s) in group '{group_name}'[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@group_app.command()
def toggle(
    group_name: str = typer.Argument(..., help="Group name"),
):
    """Toggle all lights in a group."""
    try:
        new_state = asyncio.run(GroupManager.toggle_group(group_name))
        state_str = "on" if new_state == LightState.ON else "off"
        console.print(f"[green]Group '{group_name}' toggled {state_str}[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@group_app.command()
def scene(
    group_name: str = typer.Argument(..., help="Group name"),
    scene_name: str = typer.Argument(..., help="Scene name"),
):
    """Apply a scene to all lights in a group."""
    try:
        count = asyncio.run(GroupManager.apply_scene_to_group(group_name, scene_name))
        console.print(f"[green]Applied scene '{scene_name}' to {count} light(s)[/green]")
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


# ============================================================================
# Configuration Commands
# ============================================================================

@app.command()
def alias(
    light: str = typer.Argument(..., help="Light name or IP"),
    new_alias: str = typer.Argument(..., help="New alias for the light"),
):
    """Set an alias for a light."""
    config = load_config()
    
    # Find the light
    found = False
    for name, light_config in config.lights.items():
        if name == light or light_config.ip == light:
            config.lights[name].alias = new_alias
            found = True
            break
    
    if not found:
        console.print(f"[red]Light not found: {light}[/red]")
        raise typer.Exit(1)
    
    save_config(config)
    console.print(f"[green]Alias set: {light} -> {new_alias}[/green]")


# ============================================================================
# Server Command
# ============================================================================

@app.command()
def serve(
    host: str = typer.Option("0.0.0.0", "--host", "-h", help="Host to bind to"),
    port: int = typer.Option(8000, "--port", "-p", help="Port to bind to"),
    reload: bool = typer.Option(False, "--reload", "-r", help="Enable auto-reload"),
):
    """Start the REST API server."""
    console.print("[bold blue]Starting WiZ Light Controller API...[/bold blue]")
    console.print(f"  Host: {host}")
    console.print(f"  Port: {port}")
    console.print(f"  Docs: http://{host}:{port}/docs")
    console.print()
    
    from wizctl.api.server import run_server
    run_server(host=host, port=port, reload=reload)


if __name__ == "__main__":
    app()
