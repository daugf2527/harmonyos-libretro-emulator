"""Spawn serena MCP, trigger find_symbol, then grab dashboard logs while process still alive."""
import json, os, subprocess, threading, time, queue, urllib.request


def reader(proc, q):
    for raw in proc.stdout:
        try:
            q.put(json.loads(raw.decode("utf-8").strip()))
        except Exception:
            pass


def send(proc, msg):
    proc.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
    proc.stdin.flush()


env = os.environ.copy()
env.update({
    "HTTPS_PROXY": "http://127.0.0.1:7890",
    "HTTP_PROXY": "http://127.0.0.1:7890",
    "NO_PROXY": "localhost,127.0.0.1,::1",
})

def probe(port):
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/dashboard/index.html", timeout=1)
        return True
    except Exception:
        return False


PORT_RANGE = range(24284, 24310)
before = {p for p in PORT_RANGE if probe(p)}
print(f"Pre-existing dashboards: {sorted(before)}")

proc = subprocess.Popen(
    ["cmd", "/c", "serena", "start-mcp-server", "--context", "claude-code",
     "--project", r"D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    env=env, bufsize=0,
)
q = queue.Queue()
threading.Thread(target=reader, args=(proc, q), daemon=True).start()


def find_new_dashboard():
    for _ in range(20):
        time.sleep(0.5)
        for p in PORT_RANGE:
            if p in before:
                continue
            if probe(p):
                return p
    return None


send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "verify", "version": "0.1"}}})
time.sleep(3)
send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

print("=== Searching for new dashboard port ===")
port = find_new_dashboard()
print("Dashboard:", port)

print("=== Triggering find_symbol (will start LSP) ===")
send(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
    "name": "find_symbol",
    "arguments": {"name_path_pattern": "LibretroEngine", "max_matches": 3}}})

# Drain stdout for a bit so serena log can flush
time.sleep(30)

print("=== Dashboard logs ===")
if port:
    body = json.dumps({"start_idx": 0}).encode("utf-8")
    req = urllib.request.Request(f"http://127.0.0.1:{port}/get_log_messages",
                                 data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    msgs = data.get("messages", [])
    print(f"Total messages: {len(msgs)}")
    keys = ("ERROR", "clangd", "archive", "download", "extract", "FAIL", "WARN", "ls_path",
            "binary", "_get_or_install", "Clangd executable")
    for m in msgs:
        if any(k in m for k in keys):
            print("---")
            print(m[:1200])
else:
    print("Dashboard not found")

print("\n=== Tear down ===")
try:
    proc.terminate()
    proc.wait(timeout=5)
except Exception:
    proc.kill()
