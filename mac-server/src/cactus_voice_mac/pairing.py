from __future__ import annotations

import io
import socket
from dataclasses import dataclass
from typing import Optional

from zeroconf import ServiceInfo, Zeroconf

SERVICE_TYPE = "_cactus._tcp.local."


@dataclass
class PairingInfo:
    host: str
    port: int
    token: str

    @property
    def qr_payload(self) -> str:
        return f"cactus://pair?ip={self.host}&port={self.port}&token={self.token}"


def detect_lan_ip() -> str:
    """Best-effort detection of the LAN IP this machine advertises."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
    except OSError:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def render_qr_ascii(payload: str) -> str:
    import qrcode

    qr = qrcode.QRCode(border=1)
    qr.add_data(payload)
    qr.make(fit=True)
    buf = io.StringIO()
    qr.print_ascii(out=buf, invert=True)
    return buf.getvalue()


class BonjourAdvertiser:
    def __init__(self, info: PairingInfo, instance_name: Optional[str] = None):
        self.info = info
        self.instance_name = instance_name or f"CactusVoice on {socket.gethostname().split('.')[0]}"
        self._zc: Optional[Zeroconf] = None
        self._service: Optional[ServiceInfo] = None

    def start(self) -> None:
        addr = socket.inet_aton(self.info.host)
        full_name = f"{self.instance_name}.{SERVICE_TYPE}"
        self._service = ServiceInfo(
            type_=SERVICE_TYPE,
            name=full_name,
            addresses=[addr],
            port=self.info.port,
            properties={"v": "1"},
            server=f"{socket.gethostname()}.local.",
        )
        self._zc = Zeroconf()
        self._zc.register_service(self._service)

    def stop(self) -> None:
        try:
            if self._zc and self._service:
                self._zc.unregister_service(self._service)
        finally:
            if self._zc:
                self._zc.close()
            self._zc = None
            self._service = None
