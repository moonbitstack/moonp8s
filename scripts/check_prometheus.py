#!/usr/bin/env python3
"""Feed one scrape to promtool and to a real Prometheus, and check the answers.

The exposition comes from the 09-multiprocess example: three worker processes
write three directories' worth of files, the scrape merges them, and the bytes go
out unchanged. Nothing here re-implements the library; the only code in the path
is an HTTP server that returns the bytes it was given, because a Prometheus can
only scrape over HTTP.

  promtool check metrics        the 0.0.4 text is linted strictly; the OpenMetrics
                                text must parse (promtool lints 0.0.4 samples, so
                                it reports a counter's `_total` sample as having no
                                help text — the reference client's OpenMetrics
                                output gets the same notes).
  prometheus scrape + query     the same bytes are scraped by a server and the
                                answers are compared with what the workers wrote.

Usage:
  check_prometheus.py --binary B --promtool P [--prometheus P | --docker-image I]
                      [--format text|openmetrics]
"""

import argparse
import http.server
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

CONTENT_TYPES = {
    "text": "text/plain; version=0.0.4; charset=utf-8",
    "openmetrics": "application/openmetrics-text; version=1.0.0; charset=utf-8",
}

SCRAPE_CONFIG = """\
global:
  scrape_interval: 1s
  scrape_timeout: 1s
scrape_configs:
  - job_name: moonp8s
    static_configs:
      - targets: ["{host}:{port}"]
"""


def run(binary, args):
    result = subprocess.run([binary] + args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"{binary} {' '.join(args)} failed:\n{result.stderr}")
    return result.stdout.replace("\r\n", "\n")


def exposition(binary, directory, out, fmt):
    for pid in (1, 2, 3):
        run(binary, ["--dir", directory, "--pid", str(pid)])
    args = ["--dir", directory, "--out", out]
    if fmt != "text":
        args += ["--format", fmt]
    run(binary, args)
    with open(out, encoding="utf-8", newline="") as handle:
        return handle.read()


def check_promtool(promtool, exposition, fmt):
    # Bytes, not text: a text pipe on Windows turns every line feed into a
    # carriage return and a line feed, which is not what the library wrote.
    result = subprocess.run(
        [promtool, "check", "metrics"],
        input=exposition.encode("utf-8"),
        capture_output=True,
    )
    notes = [line for line in result.stderr.decode("utf-8").splitlines() if line.strip()]
    parsing = [line for line in notes if "parsing error" in line]
    if parsing:
        sys.exit(f"promtool could not parse the {fmt} exposition:\n" + "\n".join(parsing))
    if fmt == "text":
        if result.returncode != 0:
            sys.exit("promtool check metrics failed:\n" + "\n".join(notes))
        print(f"  promtool: 0.0.4 text parses and lints clean ({result.returncode})")
    else:
        lint = [line for line in notes if "no help text" not in line]
        if lint:
            sys.exit("promtool reported something other than its 0.0.4 help notes:\n" + "\n".join(lint))
        print(
            "  promtool: OpenMetrics text parses; "
            f"{len(notes)} lint notes, all of them promtool's 0.0.4 help rule"
        )


class Querier:
    def __init__(self, base):
        self.base = base

    def query(self, expression):
        url = self.base + "/api/v1/query?query=" + urllib.parse.quote(expression)
        with urllib.request.urlopen(url, timeout=5) as response:
            payload = json.load(response)
        if payload["status"] != "success":
            raise RuntimeError(payload)
        return payload["data"]["result"]


def targets(base):
    with urllib.request.urlopen(base + "/api/v1/targets", timeout=5) as response:
        payload = json.load(response)
    return [
        (target["health"], target.get("lastError", ""))
        for target in payload["data"]["activeTargets"]
    ]


def wait_until_scraped(base, seconds=90):
    deadline = time.time() + seconds
    last = ""
    while time.time() < deadline:
        try:
            up = Querier(base).query('count(up{job="moonp8s"} == 1)')
            if up and float(up[0]["value"][1]) == 1:
                return
            last = str(targets(base))
        except Exception as error:  # the server is still starting
            last = str(error)
        time.sleep(1)
    sys.exit(f"prometheus never scraped the exposition: {last}")


def start_prometheus(args, config, workdir, port):
    if args.docker_image:
        name = "moonp8s-prometheus"
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
        subprocess.run(
            [
                "docker", "run", "-d", "--rm", "--name", name,
                "-p", f"{port}:9090",
                "--add-host", "host.docker.internal:host-gateway",
                "-v", f"{config}:/etc/prometheus/prometheus.yml:ro",
                args.docker_image,
            ],
            check=True,
            capture_output=True,
        )
        return lambda: subprocess.run(["docker", "rm", "-f", name], capture_output=True)
    process = subprocess.Popen(
        [
            args.prometheus,
            f"--config.file={config}",
            f"--storage.tsdb.path={workdir}/data",
            f"--web.listen-address=127.0.0.1:{port}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    def stop():
        process.terminate()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=30)

    return stop


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def serve(body, content_type, port, host="127.0.0.1"):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            data = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer((host, port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--promtool")
    parser.add_argument("--prometheus")
    parser.add_argument("--docker-image")
    parser.add_argument("--format", default="text", choices=sorted(CONTENT_TYPES))
    args = parser.parse_args()
    if not args.promtool and not (args.prometheus or args.docker_image):
        parser.error("give --promtool, --prometheus or --docker-image")

    with tempfile.TemporaryDirectory(prefix="moonp8s-prom-") as work:
        metrics_dir = os.path.join(work, "metrics")
        body = exposition(
            args.binary, metrics_dir, os.path.join(work, "body.txt"), args.format
        )
        print(f"{args.format}: {len(body.splitlines())} lines from three workers")

        if args.promtool:
            check_promtool(args.promtool, body, args.format)

        if not (args.prometheus or args.docker_image):
            return

        port = free_port()
        # A container reaches the host through its gateway address; a local
        # process reaches it directly.
        scrape_host = "host.docker.internal" if args.docker_image else "127.0.0.1"
        server = serve(
            body,
            CONTENT_TYPES[args.format],
            port,
            "0.0.0.0" if args.docker_image else "127.0.0.1",
        )
        config = os.path.join(work, "prometheus.yml")
        with open(config, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(SCRAPE_CONFIG.format(host=scrape_host, port=port))
        api_port = free_port()
        stop = start_prometheus(args, config, work, api_port)
        base = f"http://127.0.0.1:{api_port}"
        try:
            wait_until_scraped(base)
            querier = Querier(base)
            expected = {
                "sum(p8s_orders_total)": 60.0,
                "sum(p8s_orders_by_code_total{code=\"200\"})": 6.0,
                "sum(p8s_orders_by_code_total{code=\"500\"})": 3.0,
                "sum(p8s_request_seconds_count)": 6.0,
                "sum(p8s_request_seconds_sum)": 1.1,
                "sum(p8s_payload_bytes_count)": 3.0,
                "sum(p8s_payload_bytes_sum)": 3072.0,
                "count(p8s_queue_depth)": 1.0,
                "sum(p8s_queue_depth)": 18.0,
            }
            for expression, want in expected.items():
                result = querier.query(expression)
                if not result:
                    sys.exit(f"{expression} returned nothing")
                got = float(result[0]["value"][1])
                if abs(got - want) > 1e-9:
                    sys.exit(f"{expression} = {got}, want {want}")
                print(f"  {expression} = {got}")
            print(f"  prometheus scraped and answered {len(expected)} queries")
        finally:
            stop()
            server.shutdown()


if __name__ == "__main__":
    main()
