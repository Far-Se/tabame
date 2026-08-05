---
name: tbm-plugin-live-connected
description: Author an advanced Tabame QuickLaunch plugin for live data, dashboards, charts, timelines, logs, long-running operations, streaming chat/detail output, OAuth, browser automation, background completion, notifications, and secure storage. Use for service monitors, deployment tools, AI assistants, sync/upload tools, browser-integrated plugins, and external API clients.
---

# Tabame QuickLaunch Plugin — Live, Async & Connected Skill

> Treat this document as authoritative for live and connected plugins. Do not
> invent fields, events, browser methods, or commands. This skill focuses on
> asynchronous work, dashboards, operations, streaming, OAuth, browser bridge,
> storage, background completion, and notifications.

## 1. When to use this skill

Use this skill when the plugin performs substantial external or live work:

- API dashboards and service monitors;
- deployment, build, export, upload, sync, indexing, migration;
- chart, timeline, and log viewers;
- AI/chat/LLM plugins with streamed output;
- OAuth-authenticated API clients;
- plugins that read or automate a connected Chromium profile;
- jobs that may finish after the launcher hides.

Typical page maps:

```text
Service home      dashboard    status + chart + incidents + recent logs
Service details   dashboard    metadata + latency chart + deploy action
Deploy form       form         collect environment/version/approval
Deploy progress   operation    determinate progress + Cancel
Deploy result     diff/detail  durable outcome
```

```text
Assistant home    detail/chat  instructions and conversation
Prompt submitted  detail       stream append chunks
Result actions    Ctrl+K       copy/open/save
```

Choose views by task, not by novelty:

| Need | View |
| --- | --- |
| Overview of several related surfaces | `dashboard` |
| Metric trend or outlier | `chart` |
| Ordered event history | `timeline` |
| Live diagnostic output | `log` |
| One prominent running job | `operation` |
| Conversation feed | `chat` |
| Long streamed document/answer | `detail` + `detail.append` |
| Before/after result | `diff` |
| Exact record comparison | `table` |
| Input before an operation | `form` |

---

## 2. Plugin process and transport

A Tabame plugin is an external Python, Node.js, or Bun process activated by a
keyword. The protocol is newline-delimited JSON through stdin/stdout.

Transport rules:

1. Read stdin line by line.
2. Write exactly one serialized JSON object per line.
3. Flush after every message.
4. stdout is protocol-only; stderr is for logs.
5. Keep the stdin loop responsive. Long work and streaming must run in a worker
   thread/task.
6. Exit on `close` and EOF, after safely joining required workers.
7. Catch errors and render actionable failure states.

---

## 3. Folder, manifest, and dependencies

```text
%localappdata%\Tabame\plugins\<plugin-id>\
    plugin.json
    main.py / main.js / main.ts
    optional package.json, requirements.txt, assets/config
```

Example:

```json
{
  "id": "service-monitor",
  "name": "Service Monitor",
  "description": "Monitor and deploy services",
  "keyword": "svc",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "icon": "server",
  "args": [],
  "pip": ["requests"],
  "env": {"API_BASE":"https://api.example.com"},
  "dev": true
}
```

Required: `keyword`, `runtime`, `version`, `entry`, `id`, `name`, `description`,
`icon`. Runtime must be on `PATH`. The working directory is the plugin folder;
the process starts without a shell.

Python packages in `pip`/`requirements.txt` are installed into `.pluginlibs`.
Node/Bun packages in `package.json` are installed with npm/Bun. Lazy-load heavy
dependencies so a missing package can render a friendly error instead of
crashing.

Use `dev: true` during development for hot reload and the debug console; disable
it before sharing.

---

## 4. Relevant inbound messages

### Core lifecycle/query

```json
{"type":"init","query":"","protocol":11,"theme":{"accent":"#63A0EA","text":"#E8E8E8","background":"#1B1D23","dark":true},"locale":"en-US"}
{"type":"query","text":"api","rev":9}
{"type":"close"}
```

Use `theme` when generating matching SVG/images. `init` is followed by `query`.

### `submitQuery`

When the frame uses `inputMode: "submit"`, keystrokes are not streamed. Enter
sends the complete input:

```json
{"type":"submitQuery","text":"Explain this incident","rev":9}
```

Use for chat and LLM-style input.

### `action`

```json
{"type":"action","id":"service:api","action":"default"}
{"type":"action","id":"","action":"deploy"}
```

No `rev`. Optional `ids` and `parameters` may be present. Dashboard events may
also contain `pageId`, `panelId`, and `elementId`; dispatch using this scope.

### `chartSelect`

```json
{"type":"chartSelect","seriesId":"p95","index":4,"value":83,"rev":9}
```

Use to drill into a filtered table, timeline, or detail page.

### `cancel`

```json
{"type":"cancel","id":"deploy-42","rev":9}
```

Stop/cancel the declared operation and render a durable cancelled/result state.

### `oauth`

Reply to an OAuth command:

```json
{"type":"oauth","requestId":"login-1","code":"...","state":"..."}
```

The reply may instead contain `error` or other provider callback fields. Verify
state, exchange the code yourself, and store tokens securely.

### `browserBridge`

Reply or event from the Chromium connector:

```json
{"type":"browserBridge","requestId":"tabs-1","ok":true,"result":{}}
{"type":"browserBridge","event":"connected","data":{}}
```

Match replies by `requestId`. Handle connection/tab-change events when useful.

### `storage`

```json
{"type":"storage","requestId":"token-1","key":"token","value":"..."}
```

Response to `storage get/keys`.

### `back` and `navigate`

```json
{"type":"back","rev":9,"fromPageId":"svc:deploy","toPageId":"svc:service:api"}
{"type":"navigate","targetPageId":"svc:home","rev":9}
```

The plugin owns routing and renders the requested destination.

### Other view-specific events

- `submit` and `change` for forms;
- `loadMore` for paged tables/log-related result collections;
- `calendarNavigate`, `kanbanMove`, `toggle` if those views are intentionally
  part of the connected workflow.

---

## 5. `rev`, concurrency, and responsiveness

Tabame drops render frames whose nonzero `rev` is older than the latest query.

- Query-driven responses → echo query `rev`.
- Actions, operation updates, streamed chunks, OAuth/browser/storage replies,
  timer refreshes, and navigation → `rev: 0`.
- Loading and final query frames use the same query `rev`.
- Every `detail.append` frame uses `rev: 0`.

The host prevents stale UI, but the plugin must still protect its own state:

- keep an operation/request ID;
- ignore callbacks for replaced operations;
- use locks when multiple threads mutate state;
- cancel requests when supported;
- never write partial/interleaved JSON from multiple workers—serialize writes
  through one `send()` lock.

Python thread-safe sender:

```python
import json, sys, threading
send_lock = threading.Lock()

def send(message):
    line = json.dumps(message, ensure_ascii=False)
    with send_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
```

---

## 6. Host commands

### General UI commands

| Command | Fields | Effect |
| --- | --- | --- |
| `copy` | `text` | Copy with toast. |
| `paste` | `text` | Paste into previous window and hide. |
| `open` | `url` or `path` | Open external resource. |
| `hide` | — | Hide launcher. |
| `toast` | `text`, optional `style`, `progress` | Transient or pinned progress feedback. |
| `setQuery` | `text` | Rewrite post-keyword query. |
| `notify` | optional `title`, `text` | Native Windows notification. |

A `toast` with `style: "progress"` stays pinned until replaced. Add `progress`
from 0–1 for a determinate ring.

### Persistent storage

```jsonc
{
  "type":"command",
  "command":"storage",
  "op":"set",
  "key":"token",
  "value":"secret-token",
  "secret":true
}
```

Operations: `set`, `get`, `delete`, `keys`. `get`/`keys` reply with `storage` and
echo `requestId`. Plain values are stored in `.tabame-store.json`; secret string
values use Windows Credential Manager and are not listed by `keys`.

### Background completion

```json
{"type":"command","command":"background","timeout":60}
```

Send `background` **before** `hide` when a job must continue after the launcher
closes. Default grace is 30 seconds; maximum is 300. While detached, frames and
ordinary UI commands are dropped, but `storage` and `notify` still work.

### OAuth

```jsonc
{
  "type":"command",
  "command":"oauth",
  "authorizationUrl":"https://provider.example/authorize?redirect_uri={redirectUri}&state=...",
  "requestId":"login-1",
  "timeout":120
}
```

The URL must contain the literal `{redirectUri}` placeholder. Tabame starts an
ephemeral loopback callback listener, substitutes an encoded URI, and opens the
URL. Exchange the returned code yourself. Store access/refresh tokens with
`storage` and `secret: true`.

### Browser bridge

```jsonc
{
  "type":"command",
  "command":"browserBridge",
  "op":"status",
  "requestId":"bridge-status"
}
```

```jsonc
{
  "type":"command",
  "command":"browserBridge",
  "op":"request",
  "requestId":"page-title-1",
  "method":"javascript.execute",
  "params":{
    "tabId":42,
    "code":"return { title: document.title, url: location.href, selector: input.selector };",
    "input":{"selector":"main"}
  },
  "timeoutMs":30000
}
```

`javascript.execute` rules:

- `code` is required, may use `await`, and returns data through `return`;
- `input` is any JSON value exposed to the script as `input`;
- returned data must be JSON-serializable;
- result maximum is 128 KiB; input/result transport maximum is 192 KiB;
- `tabId` defaults to active tab;
- use bridge methods such as `tabs.open`, `tabs.list`, and `tabs.close` to own
  temporary-tab lifecycle;
- `world` defaults to `USER_SCRIPT`; request `MAIN` only when page JS globals are
  required;
- `allFrames: true` or `frameIds` targets frames;
- `injectImmediately: true` skips normal document-idle preference;
- only HTTP(S) tabs are scriptable;
- Chromium's Allow User Scripts toggle must be enabled for the companion
  extension.

This capability can read/change authenticated pages in the connected profile.
Only install browser-capable plugins you trust.

---

## 7. Pages, frames, and dashboard event scope

Example service dashboard frame:

```jsonc
{
  "type":"render",
  "rev":0,
  "view":"dashboard",
  "page":{
    "id":"svc:service:api",
    "title":"API Service",
    "history":"push",
    "preserveState":true,
    "breadcrumbs":[{"id":"svc:home","label":"Services"}]
  },
  "elementId":"service-dashboard",
  "placeholder":"Search service data…",
  "actions":[
    {"id":"refresh","title":"Refresh","icon":"refresh"},
    {"id":"sign-out","title":"Sign out","icon":"lock"}
  ],
  "floatingAction":{"id":"deploy","title":"Deploy","icon":"run"},
  "dashboard":{
    "layout":"stack",
    "panels":[]
  },
  "items":[]
}
```

Page rules:

- stable conceptual `page.id`;
- `push` for forward destinations, `replace` for redirects, `none` for refresh;
- breadcrumbs list ancestors only;
- handle `back.toPageId` and `navigate.targetPageId`;
- `preserveState: true` when selection/scroll/form state should survive revisit;
- use `canGoBack: true` only for manual sub-screens outside page history.

Dashboard scope:

Every panel must have a stable `id`, title, view, and intentional height. Its
child may also have `elementId`. Interactive events may include:

```text
pageId + panelId + elementId + normal event fields
```

Dispatch using all available scope. Do not guess solely from item IDs.

---

## 8. Dashboard, chart, timeline, log, operation, diff, chat, and detail

### `dashboard`

A dashboard composes normal view payloads:

```jsonc
{
  "view":"dashboard",
  "dashboard":{
    "layout":"stack",
    "panels":[
      {
        "id":"status",
        "title":"Status",
        "height":160,
        "view":"detail",
        "elementId":"status-detail",
        "detail":{"markdown":"## Healthy\n\nAll checks passed."}
      },
      {
        "id":"latency",
        "title":"Latency",
        "height":240,
        "view":"chart",
        "elementId":"latency-chart",
        "chart":{
          "title":"p95 latency",
          "series":[
            {"id":"p95","label":"p95","values":[24,31,27,45],"color":"#63A0EA"}
          ]
        }
      },
      {
        "id":"events",
        "title":"Recent events",
        "height":260,
        "view":"timeline",
        "elementId":"event-timeline",
        "items":[
          {"id":"event:1","timestamp":"10:42","title":"Deploy completed","icon":"check"}
        ]
      }
    ]
  }
}
```

Use 2–5 purposeful panels. `stack` reads as a report; `tabs` suits peer surfaces.
If one panel becomes a primary task, Enter or a visible action should open it as
a full page.

### `chart`

```jsonc
{
  "view":"chart",
  "chart":{
    "title":"Latency",
    "series":[
      {"id":"p50","label":"p50","values":[12,15,14]},
      {"id":"p95","label":"p95","values":[24,31,29],"color":"#63A0EA"}
    ]
  }
}
```

Series IDs are stable; values are index-aligned numbers. A click sends
`chartSelect`. Charts should answer a named question, not merely decorate.

### `timeline`

Each item uses `timestamp`, icon, title, subtitle, and accessories. Sort
intentionally and consistently—newest-first for activity feeds, oldest-first for
process narratives.

```jsonc
{
  "view":"timeline",
  "items":[
    {"id":"e1","timestamp":"10:42","title":"Build started","icon":"run"},
    {"id":"e2","timestamp":"10:45","title":"Build passed","icon":"check"}
  ]
}
```

### `log`

```jsonc
{
  "view":"log",
  "log":{
    "follow":true,
    "wrap":false,
    "lines":[
      {"id":"1","timestamp":"10:42:01","level":"info","source":"build","text":"Starting"},
      {"id":"2","timestamp":"10:42:04","level":"success","source":"build","text":"Done"}
    ]
  }
}
```

Levels: `trace`, `debug`, `info`, `warn`, `error`, `success`. With `follow: true`,
the view follows the end while the user remains at the end; scrolling upward
detaches.

### `operation`

```jsonc
{
  "view":"operation",
  "operation":{
    "id":"deploy-42",
    "title":"Deploying API",
    "detail":"Uploading release artifacts",
    "progress":0.4,
    "cancellable":true
  }
}
```

Omit progress for indeterminate work. Update with `rev: 0`. Handle `cancel` and
finish with a durable detail/diff/refreshed destination. The `operation` field
may also accompany another view as a progress strip.

### `diff`

```jsonc
{
  "view":"diff",
  "diff":{
    "mode":"unified",
    "oldLabel":"Before",
    "newLabel":"After",
    "text":"-TIMEOUT=20\n+TIMEOUT=30"
  }
}
```

`mode` is `unified` or `split`. For precise line numbers, use
`lines:[{type,text,oldLine?,newLine?}]`, where type is add/remove/context/header.

### `chat`

A chat frame is a message feed. Each item uses `title` as author, `subtitle` as
body, optional avatar `icon`, accessories for time, and optional `images` with
HTTP(S) attachments. Pair with `inputMode: "submit"`.

```jsonc
{
  "view":"chat",
  "inputMode":"submit",
  "items":[
    {"id":"m1","title":"You","subtitle":"Show recent failures"},
    {"id":"m2","title":"Assistant","subtitle":"Three builds failed today."}
  ]
}
```

### `detail` and streaming append

Initial frame:

```jsonc
{
  "view":"detail",
  "inputMode":"submit",
  "detail":{
    "wide":true,
    "markdown":"# Assistant\n\nAsk a question."
  }
}
```

Streaming chunk:

```jsonc
{
  "type":"render",
  "rev":0,
  "view":"detail",
  "inputMode":"submit",
  "detail":{"append":"next text chunk"}
}
```

`append` adds to the current markdown instead of replacing it. The view follows
the bottom while the user is reading the end; scrolling up detaches.

---

## 9. Forms and action parameters for operations

Use a full form when deployment/export/sync parameters need labels, validation,
dependencies, or editing:

```jsonc
{
  "view":"form",
  "form":{
    "title":"Deploy Service",
    "submitLabel":"Deploy",
    "fields":[
      {
        "id":"environment",
        "type":"dropdown",
        "label":"Environment",
        "required":true,
        "options":["staging","production"]
      },
      {
        "id":"version",
        "type":"text",
        "label":"Version",
        "required":true
      },
      {
        "id":"approved",
        "type":"checkbox",
        "label":"I approve this deployment",
        "value":false
      }
    ]
  }
}
```

Use action `parameters` only for one compact choice:

```jsonc
{
  "id":"restart",
  "title":"Restart service",
  "icon":"refresh",
  "confirm":true,
  "parameters":[
    {"id":"mode","type":"dropdown","label":"Mode","options":["graceful","immediate"]}
  ]
}
```

Form field types and validation follow the normal Tabame form contract:
`text`, `password`, `textarea`, `dropdown`, `combobox`, `checkbox`, `number`,
`date`, `filepicker`, `folderpicker`, and `tags`; host validation includes
`required`, min/max, minLength/maxLength, pattern, and validationMessage.

---

## 10. Streaming and long-running patterns

### Stream an LLM/detail answer without blocking stdin

```python
import threading


def on_submit_query(prompt):
    def run():
        send({
            "type": "render", "rev": 0, "view": "detail",
            "inputMode": "submit",
            "detail": {"wide": True, "markdown": f"# {prompt}\n\n"},
        })
        try:
            for chunk in call_streaming_service(prompt):
                send({
                    "type": "render", "rev": 0, "view": "detail",
                    "inputMode": "submit",
                    "detail": {"append": chunk},
                })
        except Exception as error:
            send({
                "type": "render", "rev": 0, "view": "detail",
                "inputMode": "submit",
                "detail": {"append": f"\n\n## Error\n\n```\n{error}\n```"},
            })

    threading.Thread(target=run, daemon=True).start()
```

### Operation lifecycle

1. Render form or receive action.
2. Create a unique operation ID.
3. Start a worker.
4. Render `operation` with `rev: 0`.
5. Update progress with `rev: 0`.
6. On `cancel`, signal the worker.
7. Render final detail/diff/error/cancelled state.

### Work after launcher closes

```python
send({"type":"command","command":"background","timeout":60})
send({"type":"command","command":"hide"})
# Continue work within granted grace.
send({"type":"command","command":"storage","op":"set","key":"last-result","value":result})
send({"type":"command","command":"notify","title":"Export","text":"Export complete"})
```

Send `background` before `hide`. Join required workers before process exit.

---

## 11. OAuth flow

Recommended state machine:

1. Read token from `storage` with `secret: true`.
2. If absent/expired, render a sign-in detail/empty state.
3. Generate and remember an unguessable OAuth `state` value.
4. Send `oauth` with an authorization URL containing `{redirectUri}`.
5. On `oauth` reply, reject mismatched state or provider error.
6. Exchange code for tokens through the provider's token endpoint.
7. Store tokens with `secret: true`.
8. Render the authenticated destination with `rev: 0`.
9. Refresh expired tokens when supported; sign out by deleting stored secrets.

Never ship secrets in `config.json`. Environment variables may hold public
configuration such as client IDs or API bases; sensitive tokens belong in secret
storage.

---

## 12. Browser bridge flow

Recommended pattern:

1. Send `browserBridge status`.
2. Render a clear disconnected/instructions state if unavailable.
3. For temporary work, open/list tabs through bridge methods and retain tab IDs.
4. Send allowlisted requests or `javascript.execute` with unique request IDs.
5. Match replies by request ID and handle errors visibly.
6. Close temporary tabs you created.
7. Treat page data as untrusted input; validate before rendering or executing
   subsequent actions.

Keep site-specific JavaScript in the plugin rather than modifying Tabame itself.
Do not execute arbitrary user-supplied JavaScript unless that is the explicit,
trusted purpose of the plugin and the risks are clearly surfaced.

---

## 13. Complete Python example: service dashboard and cancellable deploy

This self-contained example uses simulated data but demonstrates the correct
architecture for a real API client:

- dashboard with detail/chart/timeline/log panels;
- frame-level Deploy action;
- deployment form;
- cancellable operation updated from a worker thread;
- durable diff result;
- thread-safe stdout;
- page history and scoped routing.

`plugin.json`:

```json
{
  "id": "service-control",
  "name": "Service Control",
  "description": "Monitor and deploy a service",
  "keyword": "svc",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "icon": "server",
  "dev": true
}
```

`main.py`:

```python
#!/usr/bin/env python3
import json
import sys
import threading
import time
import uuid

send_lock = threading.Lock()
state_lock = threading.Lock()

state = {
    "page": "svc:home",
    "operation_id": None,
    "cancel_event": None,
    "version": "1.4.2",
    "worker": None,
}


def send(message):
    line = json.dumps(message, ensure_ascii=False)
    with send_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def page(page_id, title, history="none", breadcrumbs=None, preserve=True):
    result = {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": preserve,
    }
    if breadcrumbs:
        result["breadcrumbs"] = breadcrumbs
    return result


def render_dashboard(history="none", rev=0):
    with state_lock:
        state["page"] = "svc:home"
        current_version = state["version"]

    send({
        "type": "render",
        "rev": rev,
        "view": "dashboard",
        "page": page("svc:home", "Service Control", history),
        "elementId": "service-home",
        "placeholder": "Search service data…",
        "actions": [
            {"id": "refresh", "title": "Refresh", "icon": "refresh"},
        ],
        "floatingAction": {"id": "deploy", "title": "Deploy", "icon": "run"},
        "dashboard": {
            "layout": "stack",
            "panels": [
                {
                    "id": "status",
                    "title": "Status",
                    "height": 160,
                    "view": "detail",
                    "elementId": "status-detail",
                    "detail": {
                        "markdown": "## Healthy\n\nAll checks are passing.",
                        "metadata": [
                            {"label": "Version", "text": current_version},
                            {"label": "Region", "text": "eu-central"},
                            {"label": "Instances", "text": "3"},
                        ],
                    },
                },
                {
                    "id": "latency",
                    "title": "Latency",
                    "height": 220,
                    "view": "chart",
                    "elementId": "latency-chart",
                    "chart": {
                        "title": "p95 latency (ms)",
                        "series": [
                            {"id": "p95", "label": "p95", "values": [42, 38, 46, 51, 44, 39]},
                        ],
                    },
                },
                {
                    "id": "events",
                    "title": "Recent Events",
                    "height": 220,
                    "view": "timeline",
                    "elementId": "event-timeline",
                    "items": [
                        {"id": "event:1", "timestamp": "Today 10:42", "title": "Health check passed", "icon": "check"},
                        {"id": "event:2", "timestamp": "Yesterday", "title": f"Version {current_version} deployed", "icon": "run"},
                    ],
                },
                {
                    "id": "logs",
                    "title": "Recent Logs",
                    "height": 220,
                    "view": "log",
                    "elementId": "recent-log",
                    "log": {
                        "follow": False,
                        "wrap": False,
                        "lines": [
                            {"id": "l1", "level": "info", "source": "api", "text": "Request completed in 39 ms"},
                            {"id": "l2", "level": "success", "source": "health", "text": "All dependencies available"},
                        ],
                    },
                },
            ],
        },
        "items": [],
    })


def render_deploy_form(history="push", error=None):
    with state_lock:
        state["page"] = "svc:deploy"
        current_version = state["version"]

    form = {
        "title": "Deploy Service",
        "submitLabel": "Deploy",
        "fields": [
            {
                "id": "environment",
                "type": "dropdown",
                "label": "Environment",
                "value": "production",
                "required": True,
                "options": ["staging", "production"],
            },
            {
                "id": "version",
                "type": "text",
                "label": "Version",
                "value": current_version,
                "required": True,
                "pattern": r"^\d+\.\d+\.\d+$",
                "validationMessage": "Use semantic version format, for example 1.5.0",
            },
            {
                "id": "approved",
                "type": "checkbox",
                "label": "I approve this deployment",
                "value": False,
            },
        ],
    }
    if error:
        form["error"] = error

    send({
        "type": "render",
        "rev": 0,
        "view": "form",
        "page": page(
            "svc:deploy",
            "Deploy",
            history,
            breadcrumbs=[{"id": "svc:home", "label": "Service Control"}],
            preserve=True,
        ),
        "form": form,
    })


def render_operation(operation_id, version, progress, detail):
    send({
        "type": "render",
        "rev": 0,
        "view": "operation",
        "page": page(
            f"svc:operation:{operation_id}",
            "Deploying",
            "none",
            breadcrumbs=[{"id": "svc:home", "label": "Service Control"}],
            preserve=True,
        ),
        "operation": {
            "id": operation_id,
            "title": f"Deploying {version}",
            "detail": detail,
            "progress": progress,
            "cancellable": True,
        },
    })


def render_result(old_version, new_version, cancelled=False):
    with state_lock:
        state["page"] = "svc:result"

    if cancelled:
        send({
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page(
                "svc:result",
                "Deployment Cancelled",
                "replace",
                breadcrumbs=[{"id": "svc:home", "label": "Service Control"}],
            ),
            "detail": {"markdown": "# Deployment cancelled\n\nNo version change was applied."},
            "floatingAction": {"id": "home", "title": "Back to service", "icon": "home"},
        })
        return

    send({
        "type": "render",
        "rev": 0,
        "view": "diff",
        "page": page(
            "svc:result",
            "Deployment Complete",
            "replace",
            breadcrumbs=[{"id": "svc:home", "label": "Service Control"}],
        ),
        "diff": {
            "mode": "unified",
            "oldLabel": "Before",
            "newLabel": "After",
            "text": f"-VERSION={old_version}\n+VERSION={new_version}",
        },
        "actions": [{"id": "copy-version", "title": "Copy version", "icon": "copy"}],
        "floatingAction": {"id": "home", "title": "Back to service", "icon": "home"},
    })


def start_deploy(values):
    version = str(values.get("version", "")).strip()
    environment = str(values.get("environment", "production"))
    approved = bool(values.get("approved", False))

    if environment == "production" and not approved:
        render_deploy_form(history="none", error="Production deployments require approval")
        return

    operation_id = f"deploy-{uuid.uuid4().hex[:8]}"
    cancel_event = threading.Event()

    with state_lock:
        old_version = state["version"]
        state["operation_id"] = operation_id
        state["cancel_event"] = cancel_event

    def worker():
        steps = [
            "Preparing release",
            "Uploading artifacts",
            "Updating instances",
            "Running health checks",
            "Finalizing",
        ]
        try:
            for index, label in enumerate(steps):
                if cancel_event.is_set():
                    render_result(old_version, version, cancelled=True)
                    return
                render_operation(operation_id, version, index / len(steps), label)
                time.sleep(0.6)

            if cancel_event.is_set():
                render_result(old_version, version, cancelled=True)
                return

            with state_lock:
                state["version"] = version
            render_operation(operation_id, version, 1.0, "Complete")
            send({"type": "command", "command": "toast", "text": "Deployment complete", "style": "success"})
            render_result(old_version, version)
        except Exception as error:
            log("Deploy failed:", error)
            send({
                "type": "render",
                "rev": 0,
                "view": "detail",
                "detail": {"markdown": f"# Deployment failed\n\n```\n{error}\n```"},
                "canGoBack": True,
            })
        finally:
            with state_lock:
                state["operation_id"] = None
                state["cancel_event"] = None

    worker_thread = threading.Thread(target=worker, daemon=True)
    with state_lock:
        state["worker"] = worker_thread
    worker_thread.start()


def handle_action(message):
    action = message.get("action", "default")
    if action == "deploy":
        render_deploy_form()
    elif action == "refresh":
        send({"type": "command", "command": "toast", "text": "Dashboard refreshed"})
        render_dashboard()
    elif action == "home":
        render_dashboard(history="replace")
    elif action == "copy-version":
        with state_lock:
            version = state["version"]
        send({"type": "command", "command": "copy", "text": version})


def handle_cancel(message):
    operation_id = message.get("id")
    with state_lock:
        if operation_id == state["operation_id"] and state["cancel_event"]:
            state["cancel_event"].set()


def handle_navigation(message):
    target = message.get("toPageId") or message.get("targetPageId") or "svc:home"
    if target == "svc:home":
        render_dashboard()
    elif target == "svc:deploy":
        render_deploy_form(history="none")
    else:
        render_dashboard()


def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as error:
            log("Invalid stdin JSON:", error)
            continue

        event = message.get("type")
        try:
            if event == "close":
                with state_lock:
                    if state["cancel_event"]:
                        state["cancel_event"].set()
                break
            elif event in ("init", "query"):
                # The query belongs only to the dashboard in this demo. Ignore
                # query events on form/operation/result pages so they cannot
                # unexpectedly navigate away from the active workflow.
                with state_lock:
                    current_page = state["page"]
                if current_page == "svc:home":
                    render_dashboard(rev=message.get("rev", 0))
            elif event == "action":
                handle_action(message)
            elif event == "submit":
                start_deploy(message.get("values") or {})
            elif event == "cancel":
                handle_cancel(message)
            elif event in ("back", "navigate"):
                handle_navigation(message)
            elif event == "chartSelect":
                send({
                    "type": "command",
                    "command": "toast",
                    "text": f"Selected {message.get('seriesId')} point: {message.get('value')}",
                    "style": "info",
                })
        except Exception as error:
            log("Handler error:", error)
            send({
                "type": "render",
                "rev": 0,
                "view": "detail",
                "detail": {"markdown": f"# Error\n\n```\n{error}\n```"},
                "canGoBack": True,
            })

    with state_lock:
        worker_thread = state.get("worker")
    if worker_thread and worker_thread.is_alive():
        worker_thread.join(timeout=1.5)


if __name__ == "__main__":
    main()
```

In a real plugin, replace simulated sleeps/data with HTTP requests. Use request
timeouts, verify response shapes, and avoid holding `state_lock` while doing
network or slow filesystem work.

---

## 14. Node/Bun async event-loop equivalent

```js
"use strict";

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}
function log(...args) {
  console.error(...args);
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;

    let message;
    try {
      message = JSON.parse(line);
    } catch (error) {
      log("Invalid stdin JSON", error);
      continue;
    }

    if (message.type === "close") process.exit(0);
    // Dispatch init/query/submitQuery/action/submit/chartSelect/cancel/oauth,
    // browserBridge/storage/back/navigate here. Long work should be async and
    // operation identity/cancellation must be checked before pushing results.
  }
});
process.stdin.on("end", () => process.exit(0));
```

Node 18+ and Bun include global `fetch` and `AbortController`.

---

## 15. Errors and security

- Never crash on malformed input, HTTP errors, OAuth denial, bridge disconnect,
  or failed dependency imports.
- Use explicit request timeouts.
- Render failures in `detail` or the relevant form/page; use toast only for
  supplementary feedback.
- Never log secrets, authorization codes, access tokens, refresh tokens, or
  sensitive browser data.
- Store secrets with `storage secret:true`.
- Validate OAuth state.
- Treat browser and external API content as untrusted.
- Do not interpolate untrusted data into browser JavaScript source. Pass data via
  `params.input`.
- Clean up temporary tabs and cancel operation workers.
- Use `background` only for bounded work and respect the maximum grace period.

---

## 16. Icons

`icon` accepts a built-in name, a hex color, a `data:image/...` URI up to 2 MB,
or a `file://`/`https://` raster or SVG image.

```text
search star favorite heart home settings gear folder file document link globe
world cloud sun weather moon bolt flash terminal code calculator calc clock timer
calendar mail email message chat person user people image photo music video play
download upload copy content_copy clipboard paste edit pencil delete trash add
plus remove minus check close info warning error help tag label bookmark money
currency cart shop chart graph database server wifi bluetooth battery power lock
unlock key shield bell flag location map translate language palette color brush
emoji grid list menu app window extension plugin refresh sync gamepad game book
note run open
```

---

## 17. Live/connected checklist

- [ ] The page map distinguishes overview, input, progress, and durable result.
- [ ] Dashboard panels are purposeful, stable, and correctly scoped.
- [ ] Charts answer a named question; exact facts are available nearby.
- [ ] Long work runs outside the stdin loop.
- [ ] Multiple workers cannot interleave stdout JSON.
- [ ] Query responses echo `rev`; operation/stream/callback pushes use `rev: 0`.
- [ ] Operations have stable IDs, progress, cancellation, and final result pages.
- [ ] Streaming uses `inputMode: submit` and `detail.append` with `rev: 0`.
- [ ] OAuth URLs contain `{redirectUri}` and state is validated.
- [ ] Tokens use secret storage and are never logged.
- [ ] Browser bridge requests use unique request IDs and trusted, bounded code.
- [ ] Untrusted values are passed through `input`, not interpolated into code.
- [ ] Temporary browser tabs and workers are cleaned up.
- [ ] `background` is sent before `hide` for detached completion.
- [ ] Detached completion uses storage/notify, not render frames.
- [ ] Errors are actionable and do not crash the process.
- [ ] `close`/EOF exit cleanly and required workers are cancelled/joined.
- [ ] `dev` is disabled before distribution.

---

## 18. Ready-to-use request

> Build a Tabame QuickLaunch **live/connected plugin** in
> `<Python|Node|Bun>`. Keyword: `<keyword>`. It connects to `<API/browser/local
> process/LLM>` and must support `<dashboard/monitor/deploy/chat/sync/etc.>`.
> Design a page map with native views for overview, input, progress, logs, and
> durable results. Use correct async workers, `rev`, operation cancellation,
> streaming, storage/OAuth/browser bridge/background commands only where needed.
> Return `plugin.json`, all complete source/dependency files, install path,
> configuration steps, security notes, and an interaction walkthrough. Follow
> this skill exactly and invent no protocol fields or browser methods.
