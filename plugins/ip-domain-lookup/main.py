#!/usr/bin/env python3
"""
IP & Domain Lookup — Tabame launcher plugin.

Type an IP address -> geolocation / ISP / ASN.
Type a domain       -> DNS resolution + WHOIS (registrar, dates, name servers).
Leave it empty       -> looks up your own public IP.
"""

import sys
import json
import socket
import ipaddress
import threading
from urllib.parse import urlparse

import requests

try:
    import whois as pywhois
except Exception:
    pywhois = None

# ---------------------------------------------------------------- plumbing

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


_lock = threading.Lock()
_gen = 0
_last = {"kind": None, "text": "", "data": {}, "frame": None}


def bump_gen():
    global _gen
    with _lock:
        _gen += 1
        return _gen


def current_gen():
    with _lock:
        return _gen


# ---------------------------------------------------------------- helpers

def fetch_json(url):
    r = requests.get(url, timeout=8, headers={"User-Agent": "Tabame-IP-Lookup-Plugin"})
    r.raise_for_status()
    return r.json()


def normalize_domain(text):
    t = text.strip()
    if "://" in t:
        parsed = urlparse(t)
        t = parsed.netloc or parsed.path
    t = t.split("/")[0]
    t = t.split(":")[0]
    return t.strip(".").lower()


def registrable_guess(domain):
    parts = domain.split(".")
    if len(parts) <= 2:
        return domain
    return ".".join(parts[-2:])


def fmt_date(v):
    if v is None:
        return None
    if isinstance(v, list):
        v = v[0] if v else None
    if v is None:
        return None
    try:
        return v.strftime("%Y-%m-%d")
    except Exception:
        return str(v)


def fmt_list(v):
    if v is None:
        return None
    if isinstance(v, (list, tuple, set)):
        items = sorted({str(x) for x in v if x})
        return ", ".join(items) if items else None
    return str(v)


def flag_and_country(d):
    flag = ""
    try:
        flag = (d.get("flag") or {}).get("emoji", "") or ""
    except Exception:
        pass
    country = d.get("country", "") or ""
    return (flag + " " + country).strip()


# ---------------------------------------------------------------- actions

def frame_actions(kind, data):
    acts = []
    if kind in ("ip", "myip"):
        acts.append({"id": "copy", "title": "Copy IP", "icon": "copy", "shortcut": "ctrl+c"})
        if data.get("latitude") is not None and data.get("longitude") is not None:
            acts.append({"id": "map", "title": "Open on map", "icon": "map", "shortcut": "ctrl+m"})
        acts.append({"id": "asn", "title": "Open ASN / BGP info", "icon": "server"})
    elif kind == "domain":
        acts.append({"id": "copy", "title": "Copy domain", "icon": "copy", "shortcut": "ctrl+c"})
        acts.append({"id": "site", "title": "Open website", "icon": "open", "shortcut": "ctrl+o"})
        if data.get("raw"):
            acts.append({"id": "raw", "title": "View raw WHOIS", "icon": "document", "shortcut": "ctrl+shift+r"})
        acts.append({"id": "asn", "title": "Open ASN / BGP info", "icon": "server"})
    acts.append({"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"})
    return acts


def send_result(rev, kind, primary_text, data, markdown, metadata):
    detail = {"markdown": markdown, "metadata": metadata}
    frame = {
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "detail": detail,
        "actions": frame_actions(kind, data),
    }
    send(frame)
    with _lock:
        _last.update({"kind": kind, "text": primary_text, "data": data, "frame": detail})


# ---------------------------------------------------------------- renders

def render_intro(rev):
    md = (
        "# IP & Domain Lookup\n\n"
        "Type an **IP address** (e.g. `8.8.8.8`) or a **domain** (e.g. `example.com`) "
        "and press **Enter**.\n\n"
        "Leave it empty and press Enter to look up **your own public IP**."
    )
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "IP address or domain…",
        "detail": {"markdown": md},
    })


def render_loading(rev, text):
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "loading": True,
        "loadingText": text,
        "detail": {"markdown": ""},
    })


def render_error(rev, text, err):
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "detail": {"markdown": f"# Lookup failed\n\nCouldn't look up `{text}`.\n\n```\n{err}\n```"},
    })


def render_ip_result(rev, ip_text, d, kind):
    if isinstance(d, dict) and d.get("success") is False:
        render_error(rev, ip_text or "your IP", d.get("message", "unknown error"))
        return

    ip = d.get("ip", ip_text)
    conn = d.get("connection") or {}
    tz = d.get("timezone") or {}
    title = "Your Public IP" if kind == "myip" else "IP Lookup"

    md = [f"# {title}", f"## `{ip}`"]
    loc_bits = [b for b in [d.get("city"), d.get("region"), d.get("country")] if b]
    if loc_bits:
        md.append(", ".join(loc_bits))

    metadata = []
    if d.get("country"):
        metadata.append({"label": "Country", "text": flag_and_country(d) or d.get("country")})
    if d.get("region"):
        metadata.append({"label": "Region", "text": d.get("region")})
    if d.get("city"):
        metadata.append({"label": "City", "text": d.get("city")})
    if d.get("postal"):
        metadata.append({"label": "Postal code", "text": str(d.get("postal"))})
    if d.get("latitude") is not None and d.get("longitude") is not None:
        metadata.append({
            "label": "Coordinates",
            "text": f"{d['latitude']:.4f}, {d['longitude']:.4f}",
            "url": f"https://www.google.com/maps?q={d['latitude']},{d['longitude']}",
            "icon": "location",
        })
    if metadata:
        metadata.append({"separator": True})
    if conn.get("isp"):
        metadata.append({"label": "ISP", "text": conn.get("isp"), "icon": "wifi"})
    if conn.get("org"):
        metadata.append({"label": "Organization", "text": conn.get("org"), "icon": "server"})
    if conn.get("asn"):
        metadata.append({"label": "ASN", "text": f"AS{conn.get('asn')}"})
    if d.get("type"):
        metadata.append({"label": "IP version", "text": d.get("type")})
    if tz.get("id"):
        metadata.append({"label": "Timezone", "text": f"{tz.get('id')} ({tz.get('utc', '')})", "icon": "clock"})

    send_result(rev, kind, ip, d, "\n\n".join(md), metadata)


def render_domain_result(rev, domain, ips, w, raw, dns_err, whois_err):
    md = [f"# Domain Lookup", f"## `{domain}`"]
    if ips:
        md.append("Resolves to: " + ", ".join(f"`{ip}`" for ip in ips))
    elif dns_err:
        md.append(f"> Could not resolve this domain: {dns_err}")

    metadata = []
    if w:
        registrar = w.get("registrar")
        created = fmt_date(w.get("creation_date"))
        expires = fmt_date(w.get("expiration_date"))
        updated = fmt_date(w.get("updated_date"))
        status = fmt_list(w.get("status"))
        ns = fmt_list(w.get("name_servers"))
        org = w.get("org")
        country = w.get("country")

        if registrar:
            metadata.append({"label": "Registrar", "text": registrar, "icon": "shield"})
        if created:
            metadata.append({"label": "Created", "text": created, "icon": "calendar"})
        if expires:
            metadata.append({"label": "Expires", "text": expires, "icon": "calendar"})
        if updated:
            metadata.append({"label": "Updated", "text": updated, "icon": "calendar"})
        if status:
            metadata.append({"label": "Status", "text": status})
        if org:
            metadata.append({"label": "Registrant org", "text": org})
        if country:
            metadata.append({"label": "Registrant country", "text": country})
        if ns:
            metadata.append({"label": "Name servers", "text": ns})
    elif whois_err:
        metadata.append({"label": "WHOIS", "text": f"unavailable ({whois_err})"})

    if ips:
        if metadata:
            metadata.append({"separator": True})
        metadata.append({"label": "Resolved IP" + ("s" if len(ips) > 1 else ""), "text": ", ".join(ips)})

    send_result(rev, "domain", domain, {"ips": ips, "raw": raw}, "\n\n".join(md), metadata)


# ---------------------------------------------------------------- lookups

def do_lookup(rev, text, gen):
    try:
        if not text:
            d = fetch_json("https://ipwho.is/")
            if gen != current_gen():
                return
            render_ip_result(rev, d.get("ip", ""), d, "myip")
            return

        try:
            ipaddress.ip_address(text)
            is_ip = True
        except ValueError:
            is_ip = False

        if is_ip:
            d = fetch_json(f"https://ipwho.is/{text}")
            if gen != current_gen():
                return
            render_ip_result(rev, text, d, "ip")
        else:
            domain = normalize_domain(text)
            do_domain_lookup(rev, domain, gen)
    except Exception as e:
        if gen != current_gen():
            return
        render_error(rev, text or "your IP", e)


def do_domain_lookup(rev, domain, gen):
    ips = []
    dns_err = None
    try:
        _, _, ips = socket.gethostbyname_ex(domain)
    except Exception as e:
        dns_err = str(e)

    w = None
    raw = None
    whois_err = None
    if pywhois is not None:
        candidates = list(dict.fromkeys([domain, registrable_guess(domain)]))
        for candidate in candidates:
            try:
                w = pywhois.whois(candidate)
                raw = getattr(w, "text", None)
                if w and (w.get("domain_name") or raw):
                    break
            except Exception as e:
                whois_err = str(e)
                w = None
    else:
        whois_err = "python-whois not installed"

    if gen != current_gen():
        return
    render_domain_result(rev, domain, ips, w, raw, dns_err, whois_err)


# ---------------------------------------------------------------- entry points

def handle_start(rev, text):
    text = (text or "").strip()
    if not text:
        render_intro(rev)
        return
    gen = bump_gen()
    render_loading(rev, f"Looking up {text}…")
    threading.Thread(target=do_lookup, args=(rev, text, gen), daemon=True).start()


def handle_submit(rev, text):
    text = (text or "").strip()
    gen = bump_gen()
    label = "your public IP" if not text else text
    render_loading(rev, f"Looking up {label}…")
    threading.Thread(target=do_lookup, args=(rev, text, gen), daemon=True).start()


def handle_action(item_id, action):
    with _lock:
        last = dict(_last)
    kind = last.get("kind")
    data = last.get("data") or {}
    text = last.get("text", "")

    if action == "refresh":
        rev = 0
        gen = bump_gen()
        render_loading(rev, f"Looking up {text or 'your public IP'}…")
        threading.Thread(target=do_lookup, args=(rev, text, gen), daemon=True).start()
        return

    if action == "copy":
        if text:
            send({"type": "command", "command": "copy", "text": text})
            send({"type": "command", "command": "toast", "text": f"Copied {text}"})
        return

    if action == "map":
        lat, lon = data.get("latitude"), data.get("longitude")
        if lat is not None and lon is not None:
            send({"type": "command", "command": "open", "url": f"https://www.google.com/maps?q={lat},{lon}"})
        return

    if action == "asn":
        ip = None
        if kind in ("ip", "myip"):
            ip = data.get("ip") or text
        elif kind == "domain":
            ips = data.get("ips") or []
            ip = ips[0] if ips else None
        if ip:
            send({"type": "command", "command": "open", "url": f"https://bgp.he.net/ip/{ip}"})
        return

    if action == "site":
        if text:
            send({"type": "command", "command": "open", "url": f"https://{text}"})
        return

    if action == "raw":
        raw = data.get("raw")
        if raw:
            send({
                "type": "render",
                "rev": 0,
                "view": "detail",
                "inputMode": "submit",
                "canGoBack": True,
                "detail": {"markdown": f"# Raw WHOIS — `{text}`\n\n```\n{raw.strip()}\n```"},
            })
        return


def handle_back():
    with _lock:
        frame = _last.get("frame")
        kind = _last.get("kind")
        data = _last.get("data") or {}
    if frame:
        send({
            "type": "render",
            "rev": 0,
            "view": "detail",
            "inputMode": "submit",
            "detail": frame,
            "actions": frame_actions(kind, data),
        })
    else:
        render_intro(0)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        t = msg.get("type")
        if t == "close":
            break
        elif t in ("init", "query"):
            handle_start(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
        elif t == "submitQuery":
            handle_submit(msg.get("rev", 0), msg.get("text", ""))
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))
        elif t == "back":
            handle_back()
        # select / tab: not needed for this plugin


if __name__ == "__main__":
    main()
