from cactus_voice_mac.pairing import PairingInfo, detect_lan_ip, render_qr_ascii


def test_qr_payload_format():
    info = PairingInfo(host="10.0.0.5", port=8731, token="abc-xyz")
    assert info.qr_payload == "cactus://pair?ip=10.0.0.5&port=8731&token=abc-xyz"


def test_render_qr_ascii_returns_text():
    info = PairingInfo(host="10.0.0.5", port=8731, token="t")
    out = render_qr_ascii(info.qr_payload)
    assert isinstance(out, str)
    assert len(out) > 50


def test_detect_lan_ip_returns_ipv4_or_loopback():
    ip = detect_lan_ip()
    parts = ip.split(".")
    assert len(parts) == 4
    for p in parts:
        assert 0 <= int(p) <= 255
