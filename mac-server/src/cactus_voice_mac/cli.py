from __future__ import annotations

import os
import secrets
from pathlib import Path

import typer
import uvicorn
from rich.console import Console
from rich.panel import Panel

from .pairing import BonjourAdvertiser, PairingInfo, detect_lan_ip, render_qr_ascii
from .server import create_app

app = typer.Typer(no_args_is_help=False, add_completion=False)
console = Console()


@app.callback(invoke_without_command=True)
def main(
    pair: bool = typer.Option(False, "--pair", help="Print pairing QR + bring up server"),
    host: str = typer.Option(None, "--host", help="Override host (default 0.0.0.0)"),
    port: int = typer.Option(None, "--port", help="Override port (default $CACTUS_PORT or 8731)"),
    udid: str = typer.Option(None, "--udid", help="Target iOS Simulator UDID"),
    no_bonjour: bool = typer.Option(False, "--no-bonjour", help="Disable mDNS advertise"),
):
    from dotenv import load_dotenv

    load_dotenv()
    token = os.environ.get("CACTUS_TOKEN", "")
    if not token or token == "changeme-generate-with-secrets-module":
        token = secrets.token_urlsafe(32)
        env_path = Path(".env")
        if env_path.exists():
            env_path.write_text(env_path.read_text() + f"\nCACTUS_TOKEN={token}\n")
        else:
            env_path.write_text(f"CACTUS_TOKEN={token}\n")
        console.print(f"[yellow]Generated CACTUS_TOKEN and wrote to {env_path}[/yellow]")
        os.environ["CACTUS_TOKEN"] = token

    bind_host = host or os.environ.get("CACTUS_HOST", "0.0.0.0")
    bind_port = int(port or os.environ.get("CACTUS_PORT", "8731"))
    target_udid = udid or os.environ.get("TARGET_UDID") or None
    mobile_use_cmd = os.environ.get("MOBILE_USE_CMD", "uv run mobile-use")
    lan_ip = detect_lan_ip()

    fastapi_app = create_app(token=token, mobile_use_cmd=mobile_use_cmd, target_udid=target_udid)

    advertiser = None
    if not no_bonjour and bind_host in ("0.0.0.0", lan_ip):
        try:
            advertiser = BonjourAdvertiser(PairingInfo(host=lan_ip, port=bind_port, token=token))
            advertiser.start()
        except Exception as e:
            console.print(f"[yellow]Bonjour disabled: {e}[/yellow]")
            advertiser = None

    if pair:
        info = PairingInfo(host=lan_ip, port=bind_port, token=token)
        console.print(Panel.fit(render_qr_ascii(info.qr_payload), title="Pair iPhone"))
        console.print(f"Host: [bold]{info.host}[/bold]   Port: [bold]{info.port}[/bold]")
        console.print(f"Token: [bold]{info.token}[/bold]")
        console.print(f"Or paste manually in iOS Settings: {info.host}:{info.port} + token above")

    try:
        uvicorn.run(fastapi_app, host=bind_host, port=bind_port, log_level=os.environ.get("LOG_LEVEL", "info").lower())
    finally:
        if advertiser:
            advertiser.stop()
