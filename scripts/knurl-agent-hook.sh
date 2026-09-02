#!/bin/sh
# Knurl agent hook. Reads one JSON event on stdin, forwards a small typed
# subset to the local Knurl bridge, and always exits 0.
#
# Fail open, always: if Knurl is not running, the port is closed, or python is
# missing, the agent carries on as if this hook did not exist. This hook never
# returns a permission decision and never blocks a tool.
#
# It forwards paths and tool names only. It never reads prompts, transcripts,
# file contents, or environment.
exec /usr/bin/python3 - "${KNURL_HOOK_PROVIDER:-cursor}" "${1:-unknown}" "${KNURL_BRIDGE_PORT:-51741}" <<'PY'
import json, sys, urllib.request

provider, kind, port = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    raw = sys.stdin.read()
except Exception:
    raw = ""
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

roots = data.get("workspace_roots") or []
cwd = data.get("cwd") or (roots[0] if roots else None)

out = {
    "provider": provider,
    "session_id": str(data.get("session_id") or data.get("sessionId") or "unknown"),
    "kind": kind,
}
if cwd:
    out["working_directory"] = str(cwd)
tool = data.get("tool_name") or data.get("toolName")
if tool:
    out["tool"] = str(tool)
path = data.get("file_path") or data.get("filePath")
if path:
    out["path"] = str(path)

try:
    request = urllib.request.Request(
        "http://127.0.0.1:%s/event" % port,
        data=json.dumps(out).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(request, timeout=0.4).read()
except Exception:
    pass

sys.exit(0)
PY
