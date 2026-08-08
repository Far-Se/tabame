"""API Client — a Postman-lite Tabame launcher plugin.

Pages:
  api:home                    dashboard   latency chart, recent history, saved collections
  api:new                     form        build & send a request (curl/fetch import, header presets)
  api:response                 dashboard  status/timing, headers table, JSON tree or raw body
  api:confirm                  detail     "you're about to hit prod" gate for the New Request form
  api:history                   timeline  every past call, filterable, compare, reopen, clear
  api:collections                 tree    saved folders/requests: run/edit/duplicate/import/export
  api:runlog                        log   live output while a folder/selection runs sequentially
  api:diff                         diff   side-by-side comparison of two past responses
  api:environments                  list  variable sets, each with a color, one active at a time
  api:environment:<name>            form  edit one environment's variables + color
  api:headers                       list  named header presets
  api:headerpreset:<name>           form  edit one header preset
"""

import base64
import difflib
import json
import os
import re
import shlex
import sys
import time
import uuid
from datetime import datetime
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

try:
    import requests
except ImportError:
    requests = None

# --------------------------------------------------------------------------
# wire protocol helpers
# --------------------------------------------------------------------------


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def cmd(**kwargs):
    kwargs["type"] = "command"
    send(kwargs)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def new_id(prefix="id"):
    return f"{prefix}_{uuid.uuid4().hex[:8]}"


def now_iso():
    return datetime.now().strftime("%H:%M:%S")


COLOR_PALETTE = {
    "Gray": "#6B7280",
    "Blue": "#3B82F6",
    "Green": "#22C55E",
    "Yellow": "#EAB308",
    "Orange": "#F97316",
    "Red": "#EF4444",
    "Purple": "#A855F7",
}
COLOR_NAME_BY_HEX = {v: k for k, v in COLOR_PALETTE.items()}

# --------------------------------------------------------------------------
# state
# --------------------------------------------------------------------------

STATE = {
    "collections": [],  # [{id,type:"folder"|"request",name,parentId, ...request fields}]
    "history": [],  # [{id,timestamp, ...request fields, result:{...}}]
    "environments": {"Default": {"vars": {}, "color": "#6B7280"}},
    "activeEnv": "Default",
    "headerPresets": {},  # {name: {header: value}}
}
ROUTE = {"page_id": "api:home", "expanded": set()}
EDIT_CTX = {"id": None, "parentId": None}
CUR_REQ = {"last": None}
LAST_RESPONSE_ID = {"id": None}
JSON_EXPANDED = set()
PENDING_REQ = {"req": None}
BOOT_LOADED = False

PARENT = {
    "api:home": None,
    "api:new": "api:home",
    "api:response": "api:home",
    "api:confirm": "api:new",
    "api:history": "api:home",
    "api:collections": "api:home",
    "api:runlog": "api:collections",
    "api:diff": "api:history",
    "api:environments": "api:home",
    "api:headers": "api:home",
}


def save_state():
    try:
        cmd(command="storage", op="set", key="data", value=json.dumps(STATE))
    except Exception as e:
        log("save_state failed:", e)


# --------------------------------------------------------------------------
# small utilities
# --------------------------------------------------------------------------


def interpolate(text, env):
    if not isinstance(text, str) or not text:
        return text

    def repl(m):
        k = m.group(1).strip()
        return str(env.get(k, m.group(0)))

    return re.sub(r"\{\{\s*([^}]+?)\s*\}\}", repl, text)


def parse_kv_tags(tags, sep):
    out = {}
    for t in tags or []:
        if sep in t:
            k, v = t.split(sep, 1)
            out[k.strip()] = v.strip()
    return out


def parse_header_tags(tags):
    return parse_kv_tags(tags, ":")


def parse_param_tags(tags):
    return parse_kv_tags(tags, "=")


def method_color(m):
    return {
        "GET": "#22C55E",
        "POST": "#3B82F6",
        "PUT": "#F59E0B",
        "PATCH": "#A855F7",
        "DELETE": "#EF4444",
        "HEAD": "#6B7280",
        "OPTIONS": "#6B7280",
    }.get((m or "").upper(), "#6B7280")


def human_size(n):
    if n is None:
        return "—"
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    return f"{n / 1024 / 1024:.1f} MB"


def short_url(url, limit=60):
    u = url or ""
    return u if len(u) <= limit else u[: limit - 1] + "…"


def format_body_markdown(result):
    body = result.get("body", "")
    if not body:
        return "_Empty response body_"
    headers = result.get("headers") or {}
    ctype = headers.get("Content-Type", "") or headers.get("content-type", "")
    if "json" in ctype.lower():
        try:
            pretty = json.dumps(json.loads(body), indent=2, ensure_ascii=False)
            return f"```json\n{pretty[:150000]}\n```"
        except Exception:
            pass
    return f"```\n{body[:150000]}\n```"


def is_risky(method):
    """Heuristic: mutating verb + an active environment whose name suggests production."""
    ln = (STATE.get("activeEnv") or "").lower()
    return (method or "GET").upper() not in ("GET", "HEAD", "OPTIONS") and (
        "prod" in ln or "live" in ln
    )


def env_color(name=None):
    name = name or STATE["activeEnv"]
    return STATE["environments"].get(name, {}).get("color", "#6B7280")


def extract_json_path(body_text, path):
    try:
        data = json.loads(body_text)
    except Exception:
        return None
    cur = data
    if not path:
        return cur if not isinstance(cur, (dict, list)) else None
    for tok in re.findall(r"[^.\[\]]+|\[\d+\]", path):
        if tok.startswith("[") and tok.endswith("]"):
            idx = int(tok[1:-1])
            if isinstance(cur, list) and 0 <= idx < len(cur):
                cur = cur[idx]
            else:
                return None
        else:
            if isinstance(cur, dict) and tok in cur:
                cur = cur[tok]
            else:
                return None
    return cur


def build_curl(entry):
    parts = [
        "curl",
        "-X",
        entry.get("method", "GET"),
        shlex.quote(entry.get("url", "")),
    ]
    url = entry.get("url", "")
    params = entry.get("params") or {}
    if params:
        sep = "&" if "?" in url else "?"
        parts[-1] = shlex.quote(f"{url}{sep}{urlencode(params)}")
    for k, v in (entry.get("headers") or {}).items():
        parts += ["-H", shlex.quote(f"{k}: {v}")]
    auth_type = entry.get("authType", "none")
    auth = entry.get("auth") or {}
    if auth_type == "bearer" and auth.get("token"):
        parts += ["-H", shlex.quote(f"Authorization: Bearer {auth['token']}")]
    elif auth_type == "basic":
        parts += ["-u", shlex.quote(f"{auth.get('user', '')}:{auth.get('pass', '')}")]
    body_type = entry.get("bodyType", "none")
    if body_type == "json" and entry.get("body"):
        parts += [
            "-H",
            "Content-Type: application/json",
            "-d",
            shlex.quote(entry["body"]),
        ]
    elif body_type == "text" and entry.get("body"):
        parts += ["-d", shlex.quote(entry["body"])]
    elif body_type == "form" and entry.get("bodyForm"):
        for k, v in entry["bodyForm"].items():
            parts += ["-d", shlex.quote(f"{k}={v}")]
    return " ".join(parts)


def build_fetch_js(entry):
    headers = dict(entry.get("headers") or {})
    auth_type = entry.get("authType", "none")
    auth = entry.get("auth") or {}
    if auth_type == "bearer" and auth.get("token"):
        headers["Authorization"] = f"Bearer {auth['token']}"
    elif auth_type == "basic":
        token = base64.b64encode(
            f"{auth.get('user', '')}:{auth.get('pass', '')}".encode()
        ).decode()
        headers["Authorization"] = f"Basic {token}"
    opts = {"method": entry.get("method", "GET"), "headers": headers}
    body_type = entry.get("bodyType", "none")
    if body_type == "json" and entry.get("body"):
        opts["body"] = entry["body"]
        headers.setdefault("Content-Type", "application/json")
    elif body_type == "text" and entry.get("body"):
        opts["body"] = entry["body"]
    elif body_type == "form" and entry.get("bodyForm"):
        opts["body"] = "&".join(f"{k}={v}" for k, v in entry["bodyForm"].items())
        headers.setdefault("Content-Type", "application/x-www-form-urlencoded")
    url = entry.get("url", "")
    params = entry.get("params") or {}
    if params:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}{urlencode(params)}"
    return f'fetch("{url}", {json.dumps(opts, indent=2)});'


def to_form_values(node):
    if not node:
        return {}
    return {
        "method": node.get("method", "GET"),
        "url": node.get("url", ""),
        "environment": STATE["activeEnv"],
        "params": [f"{k}={v}" for k, v in (node.get("params") or {}).items()],
        "headers": [f"{k}: {v}" for k, v in (node.get("headers") or {}).items()],
        "bodyType": node.get("bodyType", "none"),
        "body": node.get("body", ""),
        "bodyForm": [f"{k}={v}" for k, v in (node.get("bodyForm") or {}).items()],
        "authType": node.get("authType", "none"),
        "authToken": (node.get("auth") or {}).get("token", ""),
        "authUser": (node.get("auth") or {}).get("user", ""),
        "authPass": (node.get("auth") or {}).get("pass", ""),
        "saveAs": bool(node.get("name")),
        "saveName": node.get("name", ""),
    }


# --------------------------------------------------------------------------
# curl / fetch(...) import
# --------------------------------------------------------------------------


def split_url_query(url):
    try:
        parts = urlsplit(url)
    except Exception:
        return url, {}
    params = dict(parse_qsl(parts.query, keep_blank_values=True))
    base = urlunsplit((parts.scheme, parts.netloc, parts.path, "", parts.fragment))
    return base, params


def _consume_auth_header(headers):
    """Pull an Authorization header out into authType/authToken/authUser/authPass, if present."""
    auth_type, token, user, pw = "none", "", "", ""
    for k, v in list(headers.items()):
        if k.lower() == "authorization" and isinstance(v, str):
            if v.lower().startswith("bearer "):
                auth_type, token = "bearer", v[7:].strip()
                del headers[k]
            elif v.lower().startswith("basic "):
                auth_type = "basic"
                try:
                    decoded = base64.b64decode(v[6:].strip()).decode("utf-8", "replace")
                    if ":" in decoded:
                        user, pw = decoded.split(":", 1)
                except Exception:
                    pass
                del headers[k]
            break
    return auth_type, token, user, pw


CURL_FLAG_VALUE = {
    "-X": "method",
    "--request": "method",
    "-H": "header",
    "--header": "header",
    "-d": "data",
    "--data": "data",
    "--data-raw": "data",
    "--data-binary": "data",
    "--data-ascii": "data",
    "--data-urlencode": "data-urlencode",
    "-u": "user",
    "--user": "user",
    "-b": "cookie",
    "--cookie": "cookie",
    "--url": "url",
    "-A": "skip",
    "--user-agent": "skip",
    "-e": "skip",
    "--referer": "skip",
    "-o": "skip",
    "--output": "skip",
    "--connect-timeout": "skip",
    "-m": "skip",
    "--max-time": "skip",
    "--cacert": "skip",
    "-x": "skip",
    "--proxy": "skip",
}
CURL_FLAG_NO_VALUE = {
    "-s",
    "--silent",
    "-k",
    "--insecure",
    "-L",
    "--location",
    "-i",
    "--include",
    "-v",
    "--verbose",
    "--compressed",
    "-G",
    "--get",
    "-#",
    "--progress-bar",
    "-f",
    "--fail",
    "-N",
    "--no-buffer",
    "--http1.1",
    "--http2",
}


def parse_curl(text):
    t = text.lstrip()
    t = re.sub(r"\\\s*\n", " ", t)  # bash line continuation
    t = re.sub(r"\^\s*\r?\n", " ", t)  # cmd.exe line continuation
    t = t.replace('""', '\\"')  # cmd.exe doubled-quote escaping -> posix escape
    try:
        tokens = shlex.split(t, posix=True)
    except ValueError:
        tokens = t.split()

    url = ""
    method = None
    headers = {}
    data_parts = []
    form_fields = {}
    used_get_params = False
    auth_user = ""
    auth_pass = ""

    i = 0
    while i < len(tokens):
        tok = tokens[i]
        kind = CURL_FLAG_VALUE.get(tok)
        if kind:
            val = tokens[i + 1] if i + 1 < len(tokens) else ""
            i += 2
            if kind == "method":
                method = val.upper()
            elif kind == "header" and ":" in val:
                k, v = val.split(":", 1)
                headers[k.strip()] = v.strip()
            elif kind == "data":
                data_parts.append(val)
            elif kind == "data-urlencode":
                if "=" in val:
                    k, v = val.split("=", 1)
                    form_fields[k.strip()] = v.strip()
            elif kind == "user":
                if ":" in val:
                    auth_user, auth_pass = val.split(":", 1)
                else:
                    auth_user = val
            elif kind == "cookie":
                headers["Cookie"] = val
            elif kind == "url":
                url = val
            continue
        if tok in CURL_FLAG_NO_VALUE:
            if tok in ("-G", "--get"):
                used_get_params = True
            i += 1
            continue
        if tok.startswith("-") and len(tok) > 1:
            i += 1
            continue
        if not url:
            url = tok
        i += 1

    if not url:
        return None

    body_type, body, params_extra = "none", "", {}
    if data_parts:
        if used_get_params:
            joined = "&".join(data_parts)
            params_extra = dict(parse_qsl(joined, keep_blank_values=True))
        else:
            joined = (
                "&".join(data_parts)
                if all("=" in d for d in data_parts) and len(data_parts) > 1
                else "\n".join(data_parts)
            )
            try:
                json.loads(joined)
                body_type = "json"
            except Exception:
                body_type = "text"
            body = joined
    elif form_fields:
        body_type = "form"

    if method is None:
        method = (
            "GET" if (used_get_params or not (data_parts or form_fields)) else "POST"
        )

    base_url, url_params = split_url_query(url)
    url_params.update(params_extra)

    if auth_user:
        auth_type, auth_token = "basic", ""
    else:
        auth_type, auth_token, hdr_user, hdr_pass = _consume_auth_header(headers)
        if auth_type == "basic":
            auth_user, auth_pass = hdr_user, hdr_pass

    return {
        "method": method,
        "url": base_url,
        "headers": headers,
        "params": url_params,
        "bodyType": body_type,
        "body": body,
        "bodyForm": form_fields,
        "authType": auth_type,
        "authToken": auth_token,
        "authUser": auth_user,
        "authPass": auth_pass,
    }


def _extract_balanced(text, start_idx):
    """Return the substring of a balanced {...} block starting at start_idx, respecting quoted strings."""
    depth, in_str, quote, escape = 0, False, "", False
    i, n = start_idx, len(text)
    while i < n:
        c = text[i]
        if in_str:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == quote:
                in_str = False
        else:
            if c in ('"', "'"):
                in_str, quote = True, c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return text[start_idx : i + 1]
        i += 1
    return None


def parse_fetch(text):
    m = re.search(r'fetch\(\s*["\']([^"\']+)["\']', text)
    if not m:
        return None
    url = m.group(1)
    method, headers, body_raw = "GET", {}, None
    brace_idx = text.find("{", m.end())
    if brace_idx != -1:
        obj_text = _extract_balanced(text, brace_idx)
        if obj_text:
            cleaned = re.sub(r",\s*([}\]])", r"\1", obj_text)
            try:
                opts = json.loads(cleaned)
            except Exception:
                opts = {}
            method = (opts.get("method") or "GET").upper()
            headers = dict(opts.get("headers") or {})
            body_raw = opts.get("body")

    body_type, body = "none", ""
    if isinstance(body_raw, str) and body_raw:
        body = body_raw
        try:
            json.loads(body_raw)
            body_type = "json"
        except Exception:
            body_type = "text"
    elif isinstance(body_raw, dict):
        body, body_type = json.dumps(body_raw), "json"

    auth_type, auth_token, auth_user, auth_pass = _consume_auth_header(headers)
    base_url, url_params = split_url_query(url)
    return {
        "method": method,
        "url": base_url,
        "headers": headers,
        "params": url_params,
        "bodyType": body_type,
        "body": body,
        "bodyForm": {},
        "authType": auth_type,
        "authToken": auth_token,
        "authUser": auth_user,
        "authPass": auth_pass,
    }


def parse_import(text):
    t = text.strip()
    if not t:
        return None
    fm = re.search(r"fetch\s*\(", t, re.IGNORECASE)
    cm = re.search(r"\bcurl(\.exe)?\b", t, re.IGNORECASE)
    if fm and (not cm or fm.start() < cm.start()):
        return parse_fetch(t[fm.start() :])
    if cm:
        return parse_curl(t[cm.end() :])
    return None


def parsed_to_values(parsed):
    return {
        "method": parsed.get("method", "GET"),
        "url": parsed.get("url", ""),
        "environment": STATE["activeEnv"],
        "params": [f"{k}={v}" for k, v in (parsed.get("params") or {}).items()],
        "headers": [f"{k}: {v}" for k, v in (parsed.get("headers") or {}).items()],
        "bodyType": parsed.get("bodyType", "none"),
        "body": parsed.get("body", "") or "",
        "bodyForm": [f"{k}={v}" for k, v in (parsed.get("bodyForm") or {}).items()],
        "authType": parsed.get("authType", "none"),
        "authToken": parsed.get("authToken", ""),
        "authUser": parsed.get("authUser", ""),
        "authPass": parsed.get("authPass", ""),
        "saveAs": False,
        "saveName": "",
    }


# --------------------------------------------------------------------------
# Postman / Insomnia import + export
# --------------------------------------------------------------------------


def build_full_url(n):
    url = n.get("url", "")
    params = n.get("params") or {}
    if params:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}{urlencode(params)}"
    return url


def node_to_postman_item(n):
    if n["type"] == "folder":
        children = [c for c in STATE["collections"] if c.get("parentId") == n["id"]]
        return {"name": n["name"], "item": [node_to_postman_item(c) for c in children]}
    header = [{"key": k, "value": v} for k, v in (n.get("headers") or {}).items()]
    body = None
    bt = n.get("bodyType", "none")
    if bt in ("json", "text") and n.get("body"):
        body = {"mode": "raw", "raw": n["body"]}
    elif bt == "form" and n.get("bodyForm"):
        body = {
            "mode": "urlencoded",
            "urlencoded": [{"key": k, "value": v} for k, v in n["bodyForm"].items()],
        }
    req = {
        "method": n.get("method", "GET"),
        "header": header,
        "url": {"raw": build_full_url(n)},
    }
    if body:
        req["body"] = body
    return {"name": n["name"], "request": req}


def postman_item_to_req(req_obj):
    method = (req_obj.get("method") or "GET").upper()
    url_field = req_obj.get("url")
    url = url_field.get("raw", "") if isinstance(url_field, dict) else (url_field or "")
    headers = {}
    for h in req_obj.get("header", []) or []:
        if isinstance(h, dict) and not h.get("disabled"):
            headers[h.get("key", "")] = h.get("value", "")
    body_type, body, body_form = "none", "", {}
    b = req_obj.get("body") or {}
    mode = b.get("mode")
    if mode == "raw":
        raw = b.get("raw", "")
        try:
            json.loads(raw)
            body_type = "json"
        except Exception:
            body_type = "text" if raw else "none"
        body = raw
    elif mode in ("urlencoded", "formdata"):
        body_type = "form"
        for f in b.get(mode, []) or []:
            if isinstance(f, dict) and not f.get("disabled"):
                body_form[f.get("key", "")] = f.get("value", "")
    base_url, params = split_url_query(url)
    return {
        "method": method,
        "url": base_url,
        "headers": headers,
        "params": params,
        "bodyType": body_type,
        "body": body,
        "bodyForm": body_form,
        "authType": "none",
        "auth": {"token": "", "user": "", "pass": ""},
    }


def import_postman_tree(items, parent_id):
    count = 0
    for it in items or []:
        name = it.get("name", "Untitled")
        if "item" in it:
            fid = new_id("fld")
            STATE["collections"].append(
                {"id": fid, "type": "folder", "name": name, "parentId": parent_id}
            )
            count += 1
            count += import_postman_tree(it["item"], fid)
        else:
            req = postman_item_to_req(it.get("request") or {})
            STATE["collections"].append(
                {
                    "id": new_id("req"),
                    "type": "request",
                    "name": name,
                    "parentId": parent_id,
                    **req,
                }
            )
            count += 1
    return count


def import_insomnia(data):
    """Best-effort: flattens all Insomnia requests to the root (folder nesting isn't preserved)."""
    resources = data.get("resources", []) or []
    count = 0
    for r in resources:
        if r.get("_type") != "request":
            continue
        method = (r.get("method") or "GET").upper()
        url = r.get("url", "")
        headers = {}
        for h in r.get("headers", []) or []:
            if not h.get("disabled"):
                headers[h.get("name", "")] = h.get("value", "")
        body_type, body, body_form = "none", "", {}
        b = r.get("body") or {}
        mime = b.get("mimeType", "")
        if "form" in mime:
            body_type = "form"
            for p in b.get("params", []) or []:
                if not p.get("disabled"):
                    body_form[p.get("name", "")] = p.get("value", "")
        elif b.get("text"):
            body = b.get("text", "")
            try:
                json.loads(body)
                body_type = "json"
            except Exception:
                body_type = "text"
        base_url, params = split_url_query(url)
        name = r.get("name") or url or "Untitled"
        STATE["collections"].append(
            {
                "id": new_id("req"),
                "type": "request",
                "name": name,
                "parentId": None,
                "method": method,
                "url": base_url,
                "headers": headers,
                "params": params,
                "bodyType": body_type,
                "body": body,
                "bodyForm": body_form,
                "authType": "none",
                "auth": {"token": "", "user": "", "pass": ""},
            }
        )
        count += 1
    return count


def do_import_collection(text):
    try:
        data = json.loads(text)
    except Exception:
        return 0, "unrecognized"
    if isinstance(data, dict) and "item" in data:
        return import_postman_tree(data["item"], None), "Postman"
    if isinstance(data, dict) and "resources" in data:
        return import_insomnia(data), "Insomnia"
    return 0, "unrecognized"


# --------------------------------------------------------------------------
# JSON body -> tree items
# --------------------------------------------------------------------------


def json_to_tree_items(data):
    items = []

    def add_node(key, value, node_path, depth):
        if isinstance(value, dict):
            items.append(
                {
                    "id": node_path,
                    "title": str(key),
                    "subtitle": f"{{{len(value)}}}",
                    "icon": "braces",
                    "depth": depth,
                    "expanded": node_path in JSON_EXPANDED,
                }
            )
            if node_path in JSON_EXPANDED:
                for k, v in value.items():
                    add_node(k, v, f"{node_path}.{k}", depth + 1)
        elif isinstance(value, list):
            items.append(
                {
                    "id": node_path,
                    "title": str(key),
                    "subtitle": f"[{len(value)}]",
                    "icon": "brackets",
                    "depth": depth,
                    "expanded": node_path in JSON_EXPANDED,
                }
            )
            if node_path in JSON_EXPANDED:
                for idx, v in enumerate(value):
                    add_node(f"[{idx}]", v, f"{node_path}[{idx}]", depth + 1)
        else:
            val_text = value if isinstance(value, str) else json.dumps(value)
            items.append(
                {
                    "id": node_path,
                    "title": str(key),
                    "subtitle": val_text[:120],
                    "icon": "tag",
                    "depth": depth,
                }
            )

    if isinstance(data, dict):
        for k, v in data.items():
            add_node(k, v, f"root.{k}", 0)
    elif isinstance(data, list):
        for idx, v in enumerate(data):
            add_node(f"[{idx}]", v, f"root[{idx}]", 0)
    return items


# --------------------------------------------------------------------------
# collections helpers
# --------------------------------------------------------------------------


def find_collection(node_id):
    for n in STATE["collections"]:
        if n["id"] == node_id:
            return n
    return None


def find_history(hist_id):
    for h in STATE["history"]:
        if h["id"] == hist_id:
            return h
    return None


def children_ids(parent_id):
    return [n["id"] for n in STATE["collections"] if n.get("parentId") == parent_id]


def count_children(parent_id):
    return len(children_ids(parent_id))


def gather_requests(parent_id):
    out = []
    for n in [x for x in STATE["collections"] if x.get("parentId") == parent_id]:
        if n["type"] == "request":
            out.append(n)
        else:
            out.extend(gather_requests(n["id"]))
    return out


def delete_collection_node(node_id):
    for cid in children_ids(node_id):
        delete_collection_node(cid)
    STATE["collections"] = [n for n in STATE["collections"] if n["id"] != node_id]
    ROUTE["expanded"].discard(node_id)


def save_collection_item_from_entry(name, entry, parent_id=None):
    node = {
        "id": new_id("req"),
        "type": "request",
        "name": name,
        "parentId": parent_id,
        "method": entry.get("method", "GET"),
        "url": entry.get("url", ""),
        "headers": entry.get("headers", {}),
        "params": entry.get("params", {}),
        "bodyType": entry.get("bodyType", "none"),
        "body": entry.get("body", ""),
        "bodyForm": entry.get("bodyForm", {}),
        "authType": entry.get("authType", "none"),
        "auth": entry.get("auth", {}),
    }
    STATE["collections"].append(node)
    save_state()


def build_tree_actions(node):
    if node["type"] == "folder":
        run_action = {"id": "runAll", "title": "Run All", "icon": "run"}
        if any(is_risky(c.get("method", "GET")) for c in gather_requests(node["id"])):
            run_action["confirm"] = {
                "title": f"Run all requests against {STATE['activeEnv']}?",
                "message": "This environment looks like production.",
                "confirmLabel": "Run All",
            }
        return [
            run_action,
            {"id": "newHere", "title": "New Request Here", "icon": "add"},
            {
                "id": "rename",
                "title": "Rename",
                "icon": "edit",
                "parameters": [
                    {
                        "id": "name",
                        "type": "text",
                        "label": "Name",
                        "required": True,
                        "value": node["name"],
                    }
                ],
            },
            {
                "id": "delete",
                "title": "Delete Folder",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": f"Delete '{node['name']}'?",
                    "message": "Deletes everything inside it.",
                    "confirmLabel": "Delete",
                },
            },
        ]
    run_action = {"id": "run", "title": "Run", "icon": "run"}
    if is_risky(node.get("method", "GET")):
        run_action["confirm"] = {
            "title": f"Send to {STATE['activeEnv']}?",
            "message": "This environment looks like production.",
            "confirmLabel": "Send",
        }
    return [
        run_action,
        {"id": "edit", "title": "Edit", "icon": "edit"},
        {"id": "duplicate", "title": "Duplicate", "icon": "copy"},
        {
            "id": "rename",
            "title": "Rename",
            "icon": "tag",
            "parameters": [
                {
                    "id": "name",
                    "type": "text",
                    "label": "Name",
                    "required": True,
                    "value": node["name"],
                }
            ],
        },
        {
            "id": "delete",
            "title": "Delete",
            "icon": "trash",
            "destructive": True,
            "confirm": {
                "title": f"Delete '{node['name']}'?",
                "message": "This cannot be undone.",
                "confirmLabel": "Delete",
            },
        },
    ]


def tree_item(n, depth, flat=False):
    if n["type"] == "folder":
        n_children = count_children(n["id"])
        return {
            "id": n["id"],
            "title": n["name"],
            "subtitle": f"{n_children} item" + ("" if n_children == 1 else "s"),
            "icon": "folder",
            "depth": 0 if flat else depth,
            "expanded": False if flat else (n["id"] in ROUTE["expanded"]),
            "actions": build_tree_actions(n),
        }
    return {
        "id": n["id"],
        "title": n["name"],
        "subtitle": n.get("url", ""),
        "icon": "globe",
        "depth": 0 if flat else depth,
        "accessories": [
            {"text": n.get("method", "GET"), "color": method_color(n.get("method"))}
        ],
        "actions": build_tree_actions(n),
    }


def visible_tree_items():
    items = []

    def walk(parent_id, depth):
        for n in [x for x in STATE["collections"] if x.get("parentId") == parent_id]:
            items.append(tree_item(n, depth))
            if n["type"] == "folder" and n["id"] in ROUTE["expanded"]:
                walk(n["id"], depth + 1)

    walk(None, 0)
    return items


def collection_root_item(n):
    if n["type"] == "folder":
        n_children = count_children(n["id"])
        return {
            "id": n["id"],
            "title": n["name"],
            "icon": "folder",
            "subtitle": f"{n_children} item" + ("" if n_children == 1 else "s"),
        }
    item = {
        "id": n["id"],
        "title": n["name"],
        "icon": "globe",
        "subtitle": n.get("url", ""),
        "accessories": [
            {"text": n.get("method", "GET"), "color": method_color(n.get("method"))}
        ],
    }
    if is_risky(n.get("method", "GET")):
        item["actions"] = [
            {
                "id": "default",
                "title": "Run",
                "icon": "run",
                "confirm": {
                    "title": f"Send to {STATE['activeEnv']}?",
                    "message": "This environment looks like production.",
                    "confirmLabel": "Send",
                },
            }
        ]
    return item


def history_item(h):
    result = h.get("result", {}) or {}
    if result.get("ok"):
        code = result.get("status", 0)
        subtitle = f"{code} · {result.get('elapsed', 0)} ms"
    else:
        subtitle = "Failed"
    return {
        "id": h["id"],
        "title": f"{h.get('method', '')} {short_url(h.get('url', ''))}",
        "subtitle": subtitle,
        "icon": "globe",
        "accessories": [
            {"text": h.get("method", ""), "color": method_color(h.get("method"))}
        ],
    }


def run_collection_node(node):
    if node["type"] != "request":
        render_collections(0)
        return
    req = {
        "method": node.get("method", "GET"),
        "url": node.get("url", ""),
        "headers": node.get("headers", {}),
        "params": node.get("params", {}),
        "bodyType": node.get("bodyType", "none"),
        "body": node.get("body", ""),
        "bodyForm": node.get("bodyForm", {}),
        "authType": node.get("authType", "none"),
        "auth": node.get("auth", {}),
    }
    execute_and_show(req)


def run_batch(nodes, title="Batch Run"):
    if not nodes:
        cmd(command="toast", text="Nothing to run")
        return
    ROUTE["page_id"] = "api:runlog"
    lines = []

    def flush():
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "log",
                "canGoBack": True,
                "page": {
                    "id": "api:runlog",
                    "title": title,
                    "history": "push",
                    "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
                },
                "log": {"lines": list(lines), "wrap": True},
            }
        )

    flush()
    ok_count = 0
    for n in nodes:
        req = {
            "method": n.get("method", "GET"),
            "url": n.get("url", ""),
            "headers": n.get("headers", {}),
            "params": n.get("params", {}),
            "bodyType": n.get("bodyType", "none"),
            "body": n.get("body", ""),
            "bodyForm": n.get("bodyForm", {}),
            "authType": n.get("authType", "none"),
            "auth": n.get("auth", {}),
        }
        body_payload = req["bodyForm"] if req["bodyType"] == "form" else req["body"]
        result = do_request(
            req["method"],
            req["url"],
            req["headers"],
            req["params"],
            req["bodyType"],
            body_payload,
            req["authType"],
            req["auth"],
        )
        entry = dict(req)
        entry["id"] = new_id("hist")
        entry["timestamp"] = now_iso()
        entry["result"] = result
        STATE["history"].insert(0, entry)
        label = n.get("name") or n.get("url", "")
        if result.get("ok"):
            ok_count += 1
            lines.append(
                {
                    "level": "info",
                    "text": f"OK  {n.get('method')} {label} -> {result['status']} ({result['elapsed']} ms)",
                }
            )
        else:
            lines.append(
                {
                    "level": "error",
                    "text": f"ERR {n.get('method')} {label} -> {result.get('error')}",
                }
            )
        flush()
    STATE["history"] = STATE["history"][:60]
    save_state()
    lines.append({"level": "info", "text": f"Done — {ok_count}/{len(nodes)} succeeded"})
    flush()


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------


def do_request(method, url, headers, params, body_type, body, auth_type, auth):
    if requests is None:
        return {
            "ok": False,
            "error": "The 'requests' package failed to install.",
            "elapsed": 0,
        }
    env = STATE["environments"].get(STATE["activeEnv"], {}).get("vars", {})
    url = interpolate(url, env)
    headers = {
        interpolate(k, env): interpolate(v, env) for k, v in (headers or {}).items()
    }
    params = {
        interpolate(k, env): interpolate(v, env) for k, v in (params or {}).items()
    }
    json_body = None
    data = None
    if body_type == "json" and body:
        text = interpolate(body, env)
        try:
            json_body = json.loads(text)
        except Exception:
            data = text
            headers.setdefault("Content-Type", "application/json")
    elif body_type == "text" and body:
        data = interpolate(body, env)
    elif body_type == "form" and body:
        data = {interpolate(k, env): interpolate(v, env) for k, v in body.items()}
    auth_obj = None
    if auth_type == "bearer" and auth.get("token"):
        headers["Authorization"] = f"Bearer {interpolate(auth['token'], env)}"
    elif auth_type == "basic":
        auth_obj = (
            interpolate(auth.get("user", ""), env),
            interpolate(auth.get("pass", ""), env),
        )
    t0 = time.time()
    try:
        resp = requests.request(
            method,
            url,
            headers=headers,
            params=params,
            json=json_body,
            data=data,
            auth=auth_obj,
            timeout=30,
        )
        elapsed = int((time.time() - t0) * 1000)
        return {
            "ok": True,
            "status": resp.status_code,
            "reason": resp.reason or "",
            "elapsed": elapsed,
            "size": len(resp.content or b""),
            "headers": dict(resp.headers),
            "body": resp.text[:200000],
        }
    except Exception as e:
        elapsed = int((time.time() - t0) * 1000)
        return {"ok": False, "error": str(e), "elapsed": elapsed}


def execute_and_show(req, warn_if_risky=False):
    if warn_if_risky and is_risky(req["method"]):
        PENDING_REQ["req"] = req
        render_confirm_send(req)
        return
    _run_request(req)


def _run_request(req):
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "operation",
            "page": {"id": "api:response", "title": "Sending…", "history": "none"},
            "operation": {
                "id": "send",
                "title": f"{req['method']} request",
                "detail": req["url"],
            },
        }
    )
    body_payload = req["bodyForm"] if req["bodyType"] == "form" else req["body"]
    result = do_request(
        req["method"],
        req["url"],
        req["headers"],
        req["params"],
        req["bodyType"],
        body_payload,
        req["authType"],
        req["auth"],
    )
    entry = dict(req)
    entry["id"] = new_id("hist")
    entry["timestamp"] = now_iso()
    entry["result"] = result
    STATE["history"].insert(0, entry)
    STATE["history"] = STATE["history"][:60]
    save_state()
    render_response(entry, rev=0, push=True)


def do_resend(entry):
    req = {
        k: entry.get(k)
        for k in (
            "method",
            "url",
            "headers",
            "params",
            "bodyType",
            "body",
            "bodyForm",
            "authType",
            "auth",
        )
    }
    execute_and_show(req)


def render_confirm_send(req):
    ROUTE["page_id"] = "api:confirm"
    name = STATE["activeEnv"]
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "page": {
                "id": "api:confirm",
                "title": "Confirm Send",
                "history": "push",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "detail": {
                "markdown": f"### ⚠️ Send **{req['method']}** to `{req['url']}`?\n\n"
                f"The active environment looks like production.",
                "metadata": [
                    {"label": "Environment", "text": name, "color": env_color(name)},
                    {"label": "Method", "text": req["method"]},
                ],
            },
            "floatingAction": [
                {
                    "id": "sendAnyway",
                    "title": "Send Anyway",
                    "icon": "warning",
                    "destructive": True,
                },
                {"id": "cancel", "title": "Cancel", "icon": "close"},
            ],
        }
    )


# --------------------------------------------------------------------------
# render: home
# --------------------------------------------------------------------------


def render_home(rev, filter_text=""):
    ROUTE["page_id"] = "api:home"
    history = STATE["history"]
    recent = history[:5]
    durations = [
        h.get("result", {}).get("elapsed", 0)
        for h in history[:10]
        if h.get("result", {}).get("ok")
    ]
    panels = []
    if durations:
        panels.append(
            {
                "id": "stats",
                "title": "Latency (ms, last 10)",
                "view": "chart",
                "height": 180,
                "chart": {
                    "series": [
                        {
                            "id": "latency",
                            "label": "ms",
                            "values": list(reversed(durations)),
                            "color": "#63A0EA",
                        }
                    ]
                },
            }
        )
    else:
        panels.append(
            {
                "id": "stats",
                "title": "Latency",
                "view": "detail",
                "height": 120,
                "detail": {
                    "markdown": "_No requests sent yet — hit **New Request** to get started._"
                },
            }
        )
    panels.append(
        {
            "id": "recent",
            "title": "Recent History",
            "view": "list",
            "height": 240,
            "emptyText": "No requests yet",
            "items": [history_item(h) for h in recent],
        }
    )
    root_items = [n for n in STATE["collections"] if n.get("parentId") is None][:6]
    panels.append(
        {
            "id": "collections",
            "title": "Collections",
            "view": "list",
            "height": 200,
            "emptyText": "No saved requests",
            "items": [collection_root_item(n) for n in root_items],
        }
    )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "dashboard",
            "page": {"id": "api:home", "title": "API Client", "history": "none"},
            "dashboard": {"layout": "stack", "panels": panels},
            "floatingAction": {
                "id": "newRequest",
                "title": "New Request",
                "icon": "add",
            },
            "actions": [
                {"id": "history", "title": "History", "icon": "clock"},
                {"id": "collections", "title": "Collections", "icon": "folder"},
                {"id": "environments", "title": "Environments", "icon": "settings"},
                {"id": "headers", "title": "Header Presets", "icon": "list"},
            ],
        }
    )


# --------------------------------------------------------------------------
# render: new / edit request form
# --------------------------------------------------------------------------


def render_new_form(rev, values=None, edit_id=None, parent_id=None, error=None):
    global EDIT_CTX
    ROUTE["page_id"] = "api:new"
    EDIT_CTX = {"id": edit_id, "parentId": parent_id}
    v = values or {}
    env_names = list(STATE["environments"].keys()) or ["Default"]
    preset_names = ["None"] + list(STATE.get("headerPresets", {}).keys())
    title = "Edit Request" if edit_id else "New Request"
    fields = [
        {
            "id": "importText",
            "type": "textarea",
            "label": "Paste curl or fetch(...) to autofill",
            "placeholder": "curl https://api.example.com -H 'Authorization: Bearer …' -d '{\"a\":1}'",
            "value": v.get("importText", ""),
            "watch": True,
        },
        {
            "id": "method",
            "type": "dropdown",
            "label": "Method",
            "value": v.get("method", "GET"),
            "options": ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
        },
        {
            "id": "url",
            "type": "text",
            "label": "URL",
            "required": True,
            "placeholder": "https://api.example.com/path?x={{VAR}}",
            "value": v.get("url", ""),
        },
        {
            "id": "environment",
            "type": "dropdown",
            "label": "Environment",
            "value": v.get("environment", STATE["activeEnv"]),
            "options": env_names,
        },
        {
            "id": "params",
            "type": "tags",
            "label": "Query Params",
            "description": "key=value",
            "value": v.get("params", []),
        },
        {
            "id": "headers",
            "type": "tags",
            "label": "Headers",
            "description": "Key: Value",
            "value": v.get("headers", []),
        },
        {
            "id": "headerPreset",
            "type": "dropdown",
            "label": "Apply Header Preset",
            "value": v.get("headerPreset", "None"),
            "options": preset_names,
            "watch": True,
        },
        {
            "id": "bodyType",
            "type": "dropdown",
            "label": "Body",
            "value": v.get("bodyType", "none"),
            "options": ["none", "json", "text", "form"],
        },
        {
            "id": "body",
            "type": "textarea",
            "label": "Body content",
            "value": v.get("body", ""),
            "visibleWhen": {"field": "bodyType", "in": ["json", "text"]},
        },
        {
            "id": "bodyForm",
            "type": "tags",
            "label": "Form Fields",
            "description": "key=value",
            "value": v.get("bodyForm", []),
            "visibleWhen": {"field": "bodyType", "equals": "form"},
        },
        {
            "id": "authType",
            "type": "dropdown",
            "label": "Auth",
            "value": v.get("authType", "none"),
            "options": ["none", "bearer", "basic"],
        },
        {
            "id": "authToken",
            "type": "password",
            "label": "Bearer Token",
            "value": v.get("authToken", ""),
            "visibleWhen": {"field": "authType", "equals": "bearer"},
        },
        {
            "id": "authUser",
            "type": "text",
            "label": "Username",
            "value": v.get("authUser", ""),
            "visibleWhen": {"field": "authType", "equals": "basic"},
        },
        {
            "id": "authPass",
            "type": "password",
            "label": "Password",
            "value": v.get("authPass", ""),
            "visibleWhen": {"field": "authType", "equals": "basic"},
        },
        {
            "id": "saveAs",
            "type": "checkbox",
            "label": "Save to Collection",
            "value": v.get("saveAs", bool(edit_id)),
        },
        {
            "id": "saveName",
            "type": "text",
            "label": "Save as",
            "value": v.get("saveName", ""),
            "visibleWhen": {"field": "saveAs", "truthy": True},
        },
    ]
    form_obj = {"title": title, "submitLabel": "Send", "fields": fields}
    if error:
        form_obj["error"] = error
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "page": {
                "id": "api:new",
                "title": title,
                "history": "push",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "form": form_obj,
        }
    )


def on_submit_new(values):
    url = (values.get("url") or "").strip()
    if not url:
        render_new_form(
            0,
            values=values,
            edit_id=EDIT_CTX["id"],
            parent_id=EDIT_CTX["parentId"],
            error="A URL is required.",
        )
        return
    method = values.get("method", "GET")
    STATE["activeEnv"] = values.get("environment") or STATE["activeEnv"]
    headers = parse_header_tags(values.get("headers"))
    params = parse_param_tags(values.get("params"))
    body_type = values.get("bodyType", "none")
    body = values.get("body", "")
    body_form = parse_param_tags(values.get("bodyForm"))
    auth_type = values.get("authType", "none")
    auth = {
        "token": values.get("authToken", ""),
        "user": values.get("authUser", ""),
        "pass": values.get("authPass", ""),
    }
    req = {
        "method": method,
        "url": url,
        "headers": headers,
        "params": params,
        "bodyType": body_type,
        "body": body,
        "bodyForm": body_form,
        "authType": auth_type,
        "auth": auth,
    }
    if values.get("saveAs"):
        name = (values.get("saveName") or url).strip()
        existing = find_collection(EDIT_CTX["id"]) if EDIT_CTX["id"] else None
        if existing:
            existing.update({"name": name, **req})
        else:
            STATE["collections"].append(
                {
                    "id": new_id("req"),
                    "type": "request",
                    "name": name,
                    "parentId": EDIT_CTX["parentId"],
                    **req,
                }
            )
        save_state()
    execute_and_show(req, warn_if_risky=True)


# --------------------------------------------------------------------------
# render: response
# --------------------------------------------------------------------------


def render_response(entry, rev=0, push=True):
    ROUTE["page_id"] = "api:response"
    CUR_REQ["last"] = entry
    if entry.get("id") != LAST_RESPONSE_ID["id"]:
        JSON_EXPANDED.clear()
        LAST_RESPONSE_ID["id"] = entry.get("id")

    result = entry.get("result", {}) or {}
    if result.get("ok"):
        code = result.get("status", 0)
        color = "#22C55E" if code < 300 else "#F59E0B" if code < 500 else "#EF4444"
        status_text = f"{code} {result.get('reason', '')}".strip()
    else:
        color = "#EF4444"
        status_text = "Request failed"
    meta = [
        {"label": "Status", "text": status_text, "color": color},
        {"label": "Method", "text": entry.get("method", "")},
        {"label": "Environment", "text": STATE["activeEnv"], "color": env_color()},
        {"label": "URL", "text": entry.get("url", "")},
    ]
    if result.get("ok"):
        meta += [
            {"label": "Time", "text": f"{result.get('elapsed', 0)} ms"},
            {"label": "Size", "text": human_size(result.get("size"))},
        ]
    else:
        meta.append({"label": "Error", "text": result.get("error", "Unknown error")})
    panels = [
        {
            "id": "status",
            "title": "Result",
            "view": "detail",
            "height": 210,
            "detail": {
                "markdown": f"**{entry.get('method', '')}** `{entry.get('url', '')}`",
                "metadata": meta,
            },
        }
    ]
    if result.get("ok") and result.get("headers"):
        panels.append(
            {
                "id": "headers",
                "title": "Response Headers",
                "view": "table",
                "height": 190,
                "columns": [
                    {"id": "title", "label": "Header"},
                    {"id": "value", "label": "Value"},
                ],
                "items": [
                    {"id": k, "title": k, "cells": {"value": v}}
                    for k, v in result["headers"].items()
                ],
            }
        )

    parsed_json = None
    if result.get("ok"):
        try:
            parsed_json = json.loads(result.get("body", ""))
        except Exception:
            parsed_json = None
    if isinstance(parsed_json, (dict, list)) and parsed_json:
        panels.append(
            {
                "id": "jsonBody",
                "title": "Body (JSON)",
                "view": "tree",
                "height": 320,
                "emptyText": "Empty",
                "items": json_to_tree_items(parsed_json),
            }
        )
    else:
        body_md = (
            format_body_markdown(result)
            if result.get("ok")
            else f"```\n{result.get('error', '')}\n```"
        )
        panels.append(
            {
                "id": "body",
                "title": "Body",
                "view": "detail",
                "height": 320,
                "detail": {"markdown": body_md},
            }
        )

    resend_action = {"id": "resend", "title": "Resend", "icon": "refresh"}
    if is_risky(entry.get("method", "GET")):
        resend_action["confirm"] = {
            "title": f"Resend to {STATE['activeEnv']}?",
            "message": "This environment looks like production.",
            "confirmLabel": "Resend",
        }

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "dashboard",
            "canGoBack": True,
            "page": {
                "id": "api:response",
                "title": f"{entry.get('method', '')} {short_url(entry.get('url', ''))}",
                "history": "push" if push else "replace",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "dashboard": {"layout": "stack", "panels": panels},
            "floatingAction": [
                resend_action,
                {
                    "id": "save",
                    "title": "Save",
                    "icon": "folder",
                    "parameters": [
                        {
                            "id": "name",
                            "type": "text",
                            "label": "Name",
                            "required": True,
                            "value": entry.get("name") or entry.get("url", ""),
                        }
                    ],
                },
                {
                    "id": "copyAs",
                    "title": "Copy As",
                    "icon": "copy",
                    "parameters": [
                        {
                            "id": "format",
                            "type": "dropdown",
                            "label": "Format",
                            "options": ["cURL", "fetch"],
                            "value": "cURL",
                        }
                    ],
                },
                {
                    "id": "extract",
                    "title": "Extract Variable",
                    "icon": "key",
                    "parameters": [
                        {
                            "id": "path",
                            "type": "text",
                            "label": "JSON Path (e.g. data.token)",
                            "required": True,
                        },
                        {
                            "id": "name",
                            "type": "text",
                            "label": "Save as Variable",
                            "required": True,
                        },
                    ],
                },
                {"id": "edit", "title": "Edit", "icon": "edit"},
            ],
        }
    )


def render_diff(rev, entry_a, entry_b):
    def pretty(e):
        r = e.get("result", {}) or {}
        body = r.get("body", "")
        try:
            return json.dumps(
                json.loads(body), indent=2, ensure_ascii=False
            ).splitlines()
        except Exception:
            return body.splitlines()

    diff_text = "\n".join(
        difflib.unified_diff(pretty(entry_a), pretty(entry_b), lineterm="")
    )
    if not diff_text.strip():
        diff_text = "(no differences)"
    ROUTE["page_id"] = "api:diff"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "diff",
            "canGoBack": True,
            "page": {
                "id": "api:diff",
                "title": "Compare Responses",
                "history": "push",
                "breadcrumbs": [
                    {"id": "api:home", "label": "API Client"},
                    {"id": "api:history", "label": "History"},
                ],
            },
            "diff": {
                "mode": "unified",
                "oldLabel": f"{entry_a.get('method', '')} · {entry_a.get('timestamp', '')}",
                "newLabel": f"{entry_b.get('method', '')} · {entry_b.get('timestamp', '')}",
                "text": diff_text,
            },
        }
    )


# --------------------------------------------------------------------------
# render: history
# --------------------------------------------------------------------------


def render_history(rev, filter_text=""):
    ROUTE["page_id"] = "api:history"
    ft = filter_text.lower()
    items = []
    for h in STATE["history"]:
        haystack = f"{h.get('method', '')} {h.get('url', '')}".lower()
        if ft and ft not in haystack:
            continue
        result = h.get("result", {}) or {}
        if result.get("ok"):
            code = result.get("status", 0)
            subtitle = f"{code} {result.get('reason', '')} · {result.get('elapsed', 0)} ms".strip()
        else:
            subtitle = f"Failed · {result.get('error', '')}"[:90]
        items.append(
            {
                "id": h["id"],
                "title": f"{h.get('method', '')} {short_url(h.get('url', ''))}",
                "subtitle": subtitle,
                "timestamp": h.get("timestamp", ""),
                "icon": "globe",
                "accessories": [
                    {
                        "text": h.get("method", ""),
                        "color": method_color(h.get("method")),
                    }
                ],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "timeline",
            "page": {
                "id": "api:history",
                "title": "History",
                "history": "push",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "placeholder": "Filter history…",
            "selection": {"max": 2},
            "empty": {
                "icon": "clock",
                "title": "No requests yet",
                "hint": "Send a request to see it here",
                "action": {"id": "newRequest", "title": "New Request", "icon": "add"},
            },
            "actions": [
                {"id": "compare", "title": "Compare Selected", "icon": "diff"},
                {
                    "id": "clear",
                    "title": "Clear History",
                    "icon": "trash",
                    "destructive": True,
                    "confirm": {
                        "title": "Clear all history?",
                        "message": "This cannot be undone.",
                        "confirmLabel": "Clear",
                    },
                },
            ],
            "items": items,
        }
    )


# --------------------------------------------------------------------------
# render: collections
# --------------------------------------------------------------------------


def render_collections(rev, filter_text=""):
    ROUTE["page_id"] = "api:collections"
    if filter_text:
        ft = filter_text.lower()
        matched = [
            n
            for n in STATE["collections"]
            if ft in n["name"].lower() or ft in (n.get("url") or "").lower()
        ]
        items = [tree_item(n, 0, flat=True) for n in matched]
    else:
        items = visible_tree_items()

    run_selected = {"id": "runSelected", "title": "Run Selected", "icon": "run"}
    ln = (STATE["activeEnv"] or "").lower()
    if "prod" in ln or "live" in ln:
        run_selected["confirm"] = {
            "title": f"Run selected requests against {STATE['activeEnv']}?",
            "message": "This environment looks like production.",
            "confirmLabel": "Run",
        }

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "tree",
            "page": {
                "id": "api:collections",
                "title": "Collections",
                "history": "push",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "placeholder": "Filter collections…",
            "selection": True,
            "empty": {
                "icon": "folder",
                "title": "No saved requests",
                "hint": "Save a request to build your library",
                "action": {"id": "newRequest", "title": "New Request", "icon": "add"},
            },
            "floatingAction": [
                {"id": "newFolder", "title": "New Folder", "icon": "folder"},
                {"id": "newRequest", "title": "New Request", "icon": "add"},
                run_selected,
                {
                    "id": "import",
                    "title": "Import",
                    "icon": "upload",
                    "parameters": [
                        {
                            "id": "json",
                            "type": "textarea",
                            "required": True,
                            "label": "Paste Postman or Insomnia collection JSON",
                        }
                    ],
                },
                {"id": "export", "title": "Export All", "icon": "download"},
            ],
            "items": items,
        }
    )


# --------------------------------------------------------------------------
# render: environments
# --------------------------------------------------------------------------


def render_environments(rev, filter_text=""):
    ROUTE["page_id"] = "api:environments"
    ft = filter_text.lower()
    items = []
    for name, edata in STATE["environments"].items():
        if ft and ft not in name.lower():
            continue
        variables = edata.get("vars", {})
        accessories = [{"text": "●", "color": edata.get("color", "#6B7280")}]
        if name == STATE["activeEnv"]:
            accessories.append({"text": "Active", "color": "#22C55E"})
        items.append(
            {
                "id": name,
                "title": name,
                "subtitle": f"{len(variables)} variable"
                + ("" if len(variables) == 1 else "s"),
                "icon": "settings",
                "accessories": accessories,
                "actions": [
                    {"id": "activate", "title": "Set Active", "icon": "check"},
                    {
                        "id": "delete",
                        "title": "Delete",
                        "icon": "trash",
                        "destructive": True,
                        "confirm": {
                            "title": f"Delete '{name}'?",
                            "message": "This cannot be undone.",
                            "confirmLabel": "Delete",
                        },
                    },
                ],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {
                "id": "api:environments",
                "title": "Environments",
                "history": "push",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "placeholder": "Filter environments…",
            "emptyText": "No environments",
            "floatingAction": {
                "id": "newEnv",
                "title": "New Environment",
                "icon": "add",
            },
            "items": items,
        }
    )


def render_env_editor(rev, name):
    ROUTE["page_id"] = f"api:environment:{name}"
    edata = STATE["environments"].get(name, {"vars": {}, "color": "#6B7280"})
    tags = [f"{k}={v}" for k, v in edata.get("vars", {}).items()]
    color_name = COLOR_NAME_BY_HEX.get(edata.get("color", "#6B7280"), "Gray")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "page": {
                "id": f"api:environment:{name}",
                "title": name,
                "history": "push",
                "breadcrumbs": [
                    {"id": "api:home", "label": "API Client"},
                    {"id": "api:environments", "label": "Environments"},
                ],
            },
            "form": {
                "title": f"Edit {name}",
                "submitLabel": "Save",
                "fields": [
                    {
                        "id": "name",
                        "type": "text",
                        "label": "Name",
                        "value": name,
                        "required": True,
                    },
                    {
                        "id": "color",
                        "type": "dropdown",
                        "label": "Color",
                        "value": color_name,
                        "options": list(COLOR_PALETTE.keys()),
                    },
                    {
                        "id": "vars",
                        "type": "tags",
                        "label": "Variables",
                        "description": "One per tag, as KEY=VALUE",
                        "value": tags,
                    },
                ],
            },
        }
    )


def on_submit_env(old_name, values):
    new_name = (values.get("name") or old_name).strip() or old_name
    variables = parse_param_tags(values.get("vars"))
    color_hex = COLOR_PALETTE.get(values.get("color", "Gray"), "#6B7280")
    edata = {"vars": variables, "color": color_hex}
    if new_name != old_name and new_name not in STATE["environments"]:
        STATE["environments"].pop(old_name, None)
        STATE["environments"][new_name] = edata
        if STATE["activeEnv"] == old_name:
            STATE["activeEnv"] = new_name
    else:
        new_name = old_name
        STATE["environments"][old_name] = edata
    save_state()
    cmd(command="toast", text=f"Saved '{new_name}'")
    render_environments(0)


# --------------------------------------------------------------------------
# render: header presets
# --------------------------------------------------------------------------


def render_header_presets(rev, filter_text=""):
    ROUTE["page_id"] = "api:headers"
    ft = filter_text.lower()
    items = []
    for name, hdrs in STATE.get("headerPresets", {}).items():
        if ft and ft not in name.lower():
            continue
        items.append(
            {
                "id": name,
                "title": name,
                "icon": "list",
                "subtitle": f"{len(hdrs)} header" + ("" if len(hdrs) == 1 else "s"),
                "actions": [
                    {
                        "id": "delete",
                        "title": "Delete",
                        "icon": "trash",
                        "destructive": True,
                        "confirm": {
                            "title": f"Delete '{name}'?",
                            "message": "This cannot be undone.",
                            "confirmLabel": "Delete",
                        },
                    }
                ],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {
                "id": "api:headers",
                "title": "Header Presets",
                "history": "push",
                "breadcrumbs": [{"id": "api:home", "label": "API Client"}],
            },
            "placeholder": "Filter presets…",
            "emptyText": "No header presets",
            "floatingAction": {"id": "newPreset", "title": "New Preset", "icon": "add"},
            "items": items,
        }
    )


def render_header_preset_editor(rev, name):
    ROUTE["page_id"] = f"api:headerpreset:{name}"
    hdrs = STATE.get("headerPresets", {}).get(name, {})
    tags = [f"{k}: {v}" for k, v in hdrs.items()]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "page": {
                "id": f"api:headerpreset:{name}",
                "title": name,
                "history": "push",
                "breadcrumbs": [
                    {"id": "api:home", "label": "API Client"},
                    {"id": "api:headers", "label": "Header Presets"},
                ],
            },
            "form": {
                "title": f"Edit {name}",
                "submitLabel": "Save",
                "fields": [
                    {
                        "id": "name",
                        "type": "text",
                        "label": "Name",
                        "value": name,
                        "required": True,
                    },
                    {
                        "id": "headers",
                        "type": "tags",
                        "label": "Headers",
                        "description": "Key: Value",
                        "value": tags,
                    },
                ],
            },
        }
    )


def on_submit_header_preset(old_name, values):
    new_name = (values.get("name") or old_name).strip() or old_name
    hdrs = parse_header_tags(values.get("headers"))
    presets = STATE.setdefault("headerPresets", {})
    if new_name != old_name and new_name not in presets:
        presets.pop(old_name, None)
    else:
        new_name = old_name
    presets[new_name] = hdrs
    save_state()
    cmd(command="toast", text=f"Saved '{new_name}'")
    render_header_presets(0)


# --------------------------------------------------------------------------
# navigation
# --------------------------------------------------------------------------


def render_for_page(page_id, rev=0):
    if page_id.startswith("api:environment:"):
        render_env_editor(rev, page_id.split(":", 2)[2])
        return
    if page_id.startswith("api:headerpreset:"):
        render_header_preset_editor(rev, page_id.split(":", 2)[2])
        return
    mapping = {
        "api:home": render_home,
        "api:new": lambda r: render_new_form(r),
        "api:response": lambda r: (
            render_response(CUR_REQ["last"], rev=r, push=False)
            if CUR_REQ.get("last")
            else render_home(r)
        ),
        "api:history": render_history,
        "api:collections": render_collections,
        "api:environments": render_environments,
        "api:headers": render_header_presets,
    }
    mapping.get(page_id, render_home)(rev)


def handle_back(msg):
    target = msg.get("toPageId")
    if not target:
        pid = ROUTE["page_id"]
        if pid.startswith("api:environment:"):
            target = "api:environments"
        elif pid.startswith("api:headerpreset:"):
            target = "api:headers"
        else:
            target = PARENT.get(pid, "api:home")
    render_for_page(target, 0)


def handle_navigate(msg):
    render_for_page(msg.get("targetPageId", "api:home"), 0)


def handle_toggle(msg):
    node_id = msg.get("id")
    panel_id = msg.get("panelId")
    expanded = msg.get("expanded")
    if panel_id == "jsonBody":
        if expanded:
            JSON_EXPANDED.add(node_id)
        else:
            JSON_EXPANDED.discard(node_id)
        if CUR_REQ.get("last"):
            render_response(CUR_REQ["last"], rev=0, push=False)
        return
    if expanded:
        ROUTE["expanded"].add(node_id)
    else:
        ROUTE["expanded"].discard(node_id)
    render_collections(0)


def handle_change(msg):
    if ROUTE["page_id"] != "api:new":
        return
    field_id = msg.get("id")
    values = msg.get("values", {}) or {}

    if field_id == "importText":
        text = (values.get("importText") or "").strip()
        if not text:
            return
        parsed = parse_import(text)
        if not parsed:
            return
        new_values = parsed_to_values(parsed)
        new_values["importText"] = ""
        new_values["saveAs"] = values.get("saveAs", False)
        new_values["saveName"] = values.get("saveName", "")
        render_new_form(
            0, values=new_values, edit_id=EDIT_CTX["id"], parent_id=EDIT_CTX["parentId"]
        )
        source = (
            "curl" if re.search(r"\bcurl(\.exe)?\b", text, re.IGNORECASE) else "fetch"
        )
        cmd(
            command="toast",
            text=f"Imported {new_values['method']} request from {source}",
        )

    elif field_id == "headerPreset":
        preset_name = values.get("headerPreset")
        if not preset_name or preset_name == "None":
            return
        preset_headers = STATE.get("headerPresets", {}).get(preset_name)
        if not preset_headers:
            return
        current = parse_header_tags(values.get("headers"))
        current.update(preset_headers)
        new_values = dict(values)
        new_values["headers"] = [f"{k}: {v}" for k, v in current.items()]
        new_values["headerPreset"] = "None"
        render_new_form(
            0, values=new_values, edit_id=EDIT_CTX["id"], parent_id=EDIT_CTX["parentId"]
        )
        cmd(command="toast", text=f"Applied '{preset_name}' headers")


def handle_submit(msg):
    page_id = ROUTE["page_id"]
    values = msg.get("values", {})
    if page_id == "api:new":
        on_submit_new(values)
    elif page_id.startswith("api:environment:"):
        on_submit_env(page_id.split(":", 2)[2], values)
    elif page_id.startswith("api:headerpreset:"):
        on_submit_header_preset(page_id.split(":", 2)[2], values)


def handle_action(msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")
    panel_id = msg.get("panelId")
    params = msg.get("parameters") or {}
    ids = msg.get("ids") or []
    page_id = ROUTE["page_id"]

    if panel_id == "recent":
        entry = find_history(item_id)
        if entry:
            render_response(entry)
        return
    if panel_id == "collections":
        node = find_collection(item_id)
        if node:
            run_collection_node(node)
        return

    if page_id == "api:home":
        if item_id == "":
            if action == "newRequest":
                render_new_form(0)
            elif action == "history":
                render_history(0)
            elif action == "collections":
                render_collections(0)
            elif action == "environments":
                render_environments(0)
            elif action == "headers":
                render_header_presets(0)
        return

    if page_id == "api:confirm":
        if item_id == "":
            if action == "sendAnyway" and PENDING_REQ.get("req"):
                execute_and_show(PENDING_REQ["req"], warn_if_risky=False)
            elif action == "cancel" and PENDING_REQ.get("req"):
                render_new_form(
                    0,
                    values=to_form_values(PENDING_REQ["req"]),
                    edit_id=EDIT_CTX["id"],
                    parent_id=EDIT_CTX["parentId"],
                )
        return

    if page_id == "api:history":
        if item_id == "":
            if action == "clear":
                STATE["history"] = []
                save_state()
                render_history(0)
            elif action == "newRequest":
                render_new_form(0)
            elif action == "compare":
                if len(ids) != 2:
                    cmd(command="toast", text="Select exactly two requests to compare.")
                    return
                idx_map = {h["id"]: i for i, h in enumerate(STATE["history"])}
                ids_sorted = sorted(ids, key=lambda i: idx_map.get(i, 0), reverse=True)
                entry_a, entry_b = (
                    find_history(ids_sorted[0]),
                    find_history(ids_sorted[1]),
                )
                if entry_a and entry_b:
                    render_diff(0, entry_a, entry_b)
            return
        entry = find_history(item_id)
        if entry:
            render_response(entry)
        return

    if page_id == "api:collections":
        if item_id == "":
            if action == "newFolder":
                STATE["collections"].append(
                    {
                        "id": new_id("fld"),
                        "type": "folder",
                        "name": "New Folder",
                        "parentId": None,
                    }
                )
                save_state()
                render_collections(0)
            elif action == "newRequest":
                render_new_form(0)
            elif action == "runSelected":
                nodes = [find_collection(i) for i in ids]
                nodes = [n for n in nodes if n and n["type"] == "request"]
                run_batch(nodes, title="Selected Requests")
            elif action == "import":
                count, fmt = do_import_collection(params.get("json", ""))
                if count:
                    save_state()
                    cmd(command="toast", text=f"Imported {count} item(s) from {fmt}")
                    render_collections(0)
                else:
                    cmd(
                        command="toast",
                        text="Couldn't recognize that as a Postman or Insomnia export",
                    )
            elif action == "export":
                roots = [n for n in STATE["collections"] if n.get("parentId") is None]
                payload = {
                    "info": {
                        "name": "API Client Export",
                        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                    },
                    "item": [node_to_postman_item(n) for n in roots],
                }
                cmd(command="copy", text=json.dumps(payload, indent=2))
                cmd(
                    command="toast",
                    text=f"Copied {len(STATE['collections'])} item(s) as Postman JSON",
                )
            return
        node = find_collection(item_id)
        if not node:
            return
        if action == "default":
            if node["type"] == "folder":
                if node["id"] in ROUTE["expanded"]:
                    ROUTE["expanded"].discard(node["id"])
                else:
                    ROUTE["expanded"].add(node["id"])
                render_collections(0)
            else:
                run_collection_node(node)
        elif action == "run":
            run_collection_node(node)
        elif action == "runAll":
            run_batch(gather_requests(node["id"]), title=f"Running {node['name']}")
        elif action == "edit":
            render_new_form(
                0,
                values=to_form_values(node),
                edit_id=node["id"],
                parent_id=node.get("parentId"),
            )
        elif action == "duplicate":
            copy_node = dict(node)
            copy_node["id"] = new_id("req")
            copy_node["name"] = f"{node['name']} copy"
            STATE["collections"].append(copy_node)
            save_state()
            render_collections(0)
        elif action == "rename":
            new_name = (params.get("name") or "").strip()
            if new_name:
                node["name"] = new_name
                save_state()
            render_collections(0)
        elif action == "newHere":
            render_new_form(0, parent_id=node["id"])
        elif action == "delete":
            delete_collection_node(node["id"])
            save_state()
            render_collections(0)
        return

    if page_id == "api:environments":
        if item_id == "" and action == "newEnv":
            name = (params.get("name") or "").strip()
            if name and name not in STATE["environments"]:
                STATE["environments"][name] = {"vars": {}, "color": "#6B7280"}
                save_state()
                render_env_editor(0, name)
            else:
                render_environments(0)
            return
        if action == "activate":
            STATE["activeEnv"] = item_id
            save_state()
            render_environments(0)
        elif action == "delete":
            if len(STATE["environments"]) > 1:
                STATE["environments"].pop(item_id, None)
                if STATE["activeEnv"] == item_id:
                    STATE["activeEnv"] = next(iter(STATE["environments"]))
                save_state()
            render_environments(0)
        return

    if page_id == "api:headers":
        if item_id == "" and action == "newPreset":
            name = (params.get("name") or "New Preset").strip()
            presets = STATE.setdefault("headerPresets", {})
            n = name
            i = 2
            while n in presets:
                n = f"{name} {i}"
                i += 1
            presets[n] = {}
            save_state()
            render_header_preset_editor(0, n)
            return
        if action == "delete":
            STATE.get("headerPresets", {}).pop(item_id, None)
            save_state()
            render_header_presets(0)
        return

    if page_id == "api:response":
        entry = CUR_REQ.get("last")
        if item_id == "" and entry:
            if action == "resend":
                do_resend(entry)
            elif action == "save":
                name = (params.get("name") or entry.get("url", "")).strip()
                save_collection_item_from_entry(name, entry)
                cmd(command="toast", text=f"Saved '{name}' to collection")
            elif action == "copyAs":
                fmt = params.get("format", "cURL")
                if fmt == "fetch":
                    cmd(command="copy", text=build_fetch_js(entry))
                    cmd(command="toast", text="Copied as fetch(...)")
                else:
                    cmd(command="copy", text=build_curl(entry))
                    cmd(command="toast", text="Copied as cURL")
            elif action == "extract":
                name = (params.get("name") or "").strip()
                path = (params.get("path") or "").strip()
                if name:
                    result = entry.get("result", {}) or {}
                    value = extract_json_path(result.get("body", ""), path)
                    if value is not None:
                        env_name = STATE["activeEnv"]
                        STATE["environments"].setdefault(
                            env_name, {"vars": {}, "color": "#6B7280"}
                        )
                        STATE["environments"][env_name]["vars"][name] = str(value)
                        save_state()
                        cmd(
                            command="toast",
                            text=f"Saved {{{{{name}}}}} = {value}"[:120],
                        )
                    else:
                        cmd(
                            command="toast",
                            text=f"Couldn't find '{path}' in the response body",
                        )
            elif action == "edit":
                render_new_form(0, values=to_form_values(entry))
        return


# --------------------------------------------------------------------------
# main loop
# --------------------------------------------------------------------------


def loading_frame(rev):
    return {
        "type": "render",
        "rev": rev,
        "view": "dashboard",
        "loading": True,
        "loadingText": "Loading your workspace…",
        "page": {"id": "api:home", "title": "API Client", "history": "none"},
        "dashboard": {"layout": "stack", "panels": []},
    }


def migrate_state(loaded):
    for k in ("collections", "history", "environments", "activeEnv", "headerPresets"):
        if k in loaded:
            STATE[k] = loaded[k]
    migrated_envs = {}
    for name, val in STATE["environments"].items():
        if isinstance(val, dict) and "vars" in val:
            migrated_envs[name] = {
                "vars": val.get("vars") or {},
                "color": val.get("color") or "#6B7280",
            }
        else:
            migrated_envs[name] = {
                "vars": val if isinstance(val, dict) else {},
                "color": "#6B7280",
            }
    STATE["environments"] = migrated_envs or {
        "Default": {"vars": {}, "color": "#6B7280"}
    }
    if STATE["activeEnv"] not in STATE["environments"]:
        STATE["activeEnv"] = next(iter(STATE["environments"]))
    if not isinstance(STATE.get("headerPresets"), dict):
        STATE["headerPresets"] = {}


def main():
    global BOOT_LOADED
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = msg.get("type")
        try:
            if t == "close":
                break
            elif t == "init":
                cmd(command="storage", op="get", key="data", requestId="boot")
                send(loading_frame(0))
            elif t == "query":
                rev = msg.get("rev", 0)
                if not BOOT_LOADED:
                    send(loading_frame(rev))
                else:
                    text = msg.get("text", "")
                    pid = ROUTE["page_id"]
                    if pid == "api:history":
                        render_history(rev, filter_text=text)
                    elif pid == "api:collections":
                        render_collections(rev, filter_text=text)
                    elif pid == "api:environments":
                        render_environments(rev, filter_text=text)
                    elif pid == "api:headers":
                        render_header_presets(rev, filter_text=text)
            elif t == "storage":
                if msg.get("requestId") == "boot":
                    raw = msg.get("value")
                    if raw:
                        try:
                            migrate_state(json.loads(raw))
                        except Exception as e:
                            log("failed to parse stored state:", e)
                            migrate_state({})
                    else:
                        migrate_state({})
                    BOOT_LOADED = True
                    render_home(0)
            elif not BOOT_LOADED:
                pass
            elif t == "action":
                handle_action(msg)
            elif t == "toggle":
                handle_toggle(msg)
            elif t == "submit":
                handle_submit(msg)
            elif t == "back":
                handle_back(msg)
            elif t == "navigate":
                handle_navigate(msg)
            elif t == "change":
                handle_change(msg)
            # select / cancel / kanbanMove / calendarNavigate: unused by this plugin
        except Exception as e:
            log("ERROR handling", t, ":", repr(e))
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "detail": {"markdown": f"# Something went wrong\n\n```\n{e}\n```"},
                }
            )


if __name__ == "__main__":
    main()
