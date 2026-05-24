"""End-to-end MCP server smoke test - spawns each MCP via cmd /c (same as Claude Code),
walks the MCP stdio protocol (initialize + initialized + tools/list + optional tool call),
and reports per-server status. Run with serena-agent's Python so requests/etc are available."""
import json, os, sys, subprocess, threading, time, queue


def send(proc, msg):
    line = json.dumps(msg) + "\n"
    proc.stdin.write(line.encode("utf-8"))
    proc.stdin.flush()


def reader_thread(proc, q):
    for raw in proc.stdout:
        try:
            q.put(json.loads(raw.decode("utf-8").strip()))
        except Exception as e:
            q.put({"_parse_error": str(e), "_raw": raw[:200].decode("utf-8", errors="replace")})


def stderr_thread(proc, lines):
    for raw in proc.stderr:
        lines.append(raw.decode("utf-8", errors="replace").rstrip())


def recv(q, timeout):
    try:
        return q.get(timeout=timeout)
    except queue.Empty:
        return None


def run_one(name, args, env_extra, init_timeout, warmup_call=None, tool_call=None, call_timeout=20):
    print(f"\n{'='*60}\n[{name}] starting: {' '.join(args)}")
    env = os.environ.copy()
    env.update(env_extra or {})
    try:
        proc = subprocess.Popen(
            args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=env, bufsize=0, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)
        )
    except Exception as e:
        print(f"[{name}] SPAWN FAIL: {e}")
        return False

    out_q = queue.Queue()
    err_lines = []
    threading.Thread(target=reader_thread, args=(proc, out_q), daemon=True).start()
    threading.Thread(target=stderr_thread, args=(proc, err_lines), daemon=True).start()

    ok = False
    next_id = 1
    try:
        send(proc, {"jsonrpc": "2.0", "id": next_id, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "verify-mcp-e2e", "version": "0.1"}}})
        next_id += 1
        resp = recv(out_q, init_timeout)
        if not resp:
            print(f"[{name}] FAIL: no initialize response in {init_timeout}s")
            return False
        if "error" in resp:
            print(f"[{name}] FAIL initialize: {resp['error']}")
            return False
        srv = resp.get("result", {}).get("serverInfo", {})
        print(f"[{name}] initialize OK: {srv.get('name','?')} {srv.get('version','?')}")

        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        send(proc, {"jsonrpc": "2.0", "id": next_id, "method": "tools/list", "params": {}})
        next_id += 1
        resp = recv(out_q, 15)
        if not resp or "error" in resp:
            print(f"[{name}] FAIL tools/list: {resp}")
            return False
        tool_names = [t["name"] for t in resp.get("result", {}).get("tools", [])]
        print(f"[{name}] tools/list OK: {len(tool_names)} tools")
        print(f"[{name}] sample tools: {tool_names[:5]}")

        if warmup_call:
            wname, wargs = warmup_call
            if wname in tool_names:
                print(f"[{name}] warmup {wname}({wargs}) to trigger LSP ...")
                send(proc, {"jsonrpc": "2.0", "id": next_id, "method": "tools/call",
                            "params": {"name": wname, "arguments": wargs}})
                next_id += 1
                t0 = time.time()
                wresp = recv(out_q, call_timeout)
                print(f"[{name}] warmup done in {time.time()-t0:.1f}s")
                # Give LSP a beat to finish indexing
                time.sleep(5)

        if tool_call:
            tname, targs = tool_call
            if tname not in tool_names:
                print(f"[{name}] SKIP tool_call: {tname} not in tools list")
            else:
                print(f"[{name}] calling tool {tname}({targs}) ...")
                send(proc, {"jsonrpc": "2.0", "id": next_id, "method": "tools/call",
                            "params": {"name": tname, "arguments": targs}})
                next_id += 1
                t0 = time.time()
                resp = recv(out_q, call_timeout)
                dt = time.time() - t0
                if not resp:
                    print(f"[{name}] FAIL tool_call: no response in {call_timeout}s")
                    return False
                if "error" in resp:
                    print(f"[{name}] FAIL tool_call: {resp['error']}")
                    return False
                content = resp.get("result", {}).get("content", [])
                text = ""
                for c in content:
                    if c.get("type") == "text":
                        text += c.get("text", "")
                preview = text[:400].replace("\n", " | ")
                is_error_text = ("Error executing tool" in text) or ("No symbols found" in text)
                status = "EMPTY/ERROR" if is_error_text else "RESULT"
                print(f"[{name}] tool_call returned in {dt:.1f}s [{status}]: {preview}")
                if is_error_text:
                    return False

        ok = True
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
        if err_lines:
            tail = "\n  ".join(err_lines[-15:])
            print(f"[{name}] stderr tail:\n  {tail}")
    return ok


def main():
    results = {}

    # ast-grep: just need MCP stdio working (no LSP, no network at runtime)
    results["ast-grep"] = run_one(
        "ast-grep",
        ["cmd", "/c", "uvx", "--from",
         r"C:\Users\newwo\.local\share\ast-grep-mcp", "ast-grep-server"],
        env_extra={}, init_timeout=60,
    )

    # cclsp: warmup with get_diagnostics on a cpp file to start clangd LSP,
    # then find_workspace_symbols. clangd background-index can take a while.
    results["cclsp"] = run_one(
        "cclsp",
        ["cmd", "/c", "npx", "-y", "cclsp@latest"],
        env_extra={"CCLSP_CONFIG_PATH":
                   r"D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\.claude\cclsp.json"},
        init_timeout=60,
        warmup_call=("get_diagnostics", {"file_path":
                     r"D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\entry\src\main\cpp\core\engine\libretro_engine.cpp"}),
        tool_call=("find_workspace_symbols", {"query": "LibretroEngine"}),
        call_timeout=180,
    )

    # serena: initialize + find_symbol(LibretroEngine) — exercises pre-downloaded clangd
    results["serena"] = run_one(
        "serena",
        ["cmd", "/c", "serena", "start-mcp-server", "--context", "claude-code",
         "--project",
         r"D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator"],
        env_extra={
            "HTTPS_PROXY": "http://127.0.0.1:7890",
            "HTTP_PROXY": "http://127.0.0.1:7890",
            "NO_PROXY": "localhost,127.0.0.1,::1",
        },
        init_timeout=90,
        tool_call=("find_symbol", {"name_path_pattern": "LibretroEngine", "max_matches": 3}),
        call_timeout=120,
    )

    print("\n" + "="*60 + "\nSUMMARY")
    for k, v in results.items():
        print(f"  {k}: {'PASS' if v else 'FAIL'}")
    sys.exit(0 if all(results.values()) else 1)


if __name__ == "__main__":
    main()
