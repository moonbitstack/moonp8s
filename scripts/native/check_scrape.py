#!/usr/bin/env python3
"""A real Prometheus scrapes native histograms from moonp8s and from client_golang fed the same
sizes, and answers the same queries for both.

moonp8s's side is the protobuf the 10-native example prints (as hex, first line), served as it
came; client_golang's side is `scripts/native/compare -serve`. Prometheus runs with native
histograms enabled and asks for protobuf. `histogram_count` answers only for a native series, so
an empty answer means the buckets were read as classic ones.

  check_scrape.py --example BIN --golang BIN (--prometheus BIN | --docker-image IMAGE)
"""

import argparse
import http.server
import json
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

CONTENT_TYPE = "application/vnd.google.protobuf; proto=io.prometheus.client.MetricFamily; encoding=delimited"

CONFIG = """\
global:
  scrape_interval: 1s
  scrape_timeout: 1s
  scrape_protocols: [PrometheusProto, OpenMetricsText1.0.0, PrometheusText0.0.4]
scrape_configs:
  - job_name: moonp8s
    static_configs:
      - targets: ["{host}:{ours}"]
  - job_name: golang
    static_configs:
      - targets: ["{host}:{theirs}"]
"""

QUERIES = [
    'histogram_count(request_size_bytes{{job="{job}"}})',
    'histogram_sum(request_size_bytes{{job="{job}"}})',
    'histogram_quantile(0.5, request_size_bytes{{job="{job}"}})',
    'histogram_quantile(0.9, request_size_bytes{{job="{job}"}})',
    'histogram_quantile(0.99, request_size_bytes{{job="{job}"}})',
    'histogram_fraction(0, 1000, request_size_bytes{{job="{job}"}})',
    'sum by (le) (request_size_classic_bytes_bucket{{job="{job}"}})',
]


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def query(base, expression):
    url = base + "/api/v1/query?query=" + urllib.parse.quote(expression)
    with urllib.request.urlopen(url, timeout=5) as response:
        payload = json.load(response)
    if payload["status"] != "success":
        raise RuntimeError(payload)
    return sorted((r["metric"].get("le", ""), r["value"][1]) for r in payload["data"]["result"])


def serve(body, port):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass

    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--example", required=True)
    parser.add_argument("--golang", required=True)
    parser.add_argument("--prometheus")
    parser.add_argument("--docker-image")
    args = parser.parse_args()

    out = subprocess.run([args.example], capture_output=True, check=True).stdout.decode("utf-8")
    body = bytes.fromhex(out.splitlines()[0].strip())
    ours, theirs, port = free_port(), free_port(), free_port()
    serve(body, ours)
    golang = subprocess.Popen([args.golang, "-serve", f"0.0.0.0:{theirs}"])
    host = "host.docker.internal" if args.docker_image else "127.0.0.1"
    work = tempfile.mkdtemp(prefix="moonp8s-native-")
    config = f"{work}/prometheus.yml"
    with open(config, "w", encoding="utf-8") as handle:
        handle.write(CONFIG.format(host=host, ours=ours, theirs=theirs))
    flags = ["--config.file=/etc/prometheus/prometheus.yml", "--storage.tsdb.path=/prometheus",
             "--enable-feature=native-histograms"]
    if args.docker_image:
        name = "moonp8s-native-prometheus"
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
        subprocess.run(["docker", "run", "-d", "--rm", "--name", name, "-p", f"{port}:9090",
                        "--add-host", "host.docker.internal:host-gateway",
                        "-v", f"{config}:/etc/prometheus/prometheus.yml:ro", args.docker_image, *flags],
                       check=True, capture_output=True)
        stop = lambda: subprocess.run(["docker", "rm", "-f", name], capture_output=True)
    else:
        process = subprocess.Popen([args.prometheus, f"--config.file={config}", f"--storage.tsdb.path={work}/data",
                                    f"--web.listen-address=127.0.0.1:{port}", "--enable-feature=native-histograms"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        stop = process.terminate
    base = f"http://127.0.0.1:{port}"
    failures = 0
    try:
        deadline = time.time() + 120
        while True:
            try:
                if all(query(base, QUERIES[0].format(job=job)) for job in ("moonp8s", "golang")):
                    break
            except Exception:  # Prometheus is still starting
                pass
            if time.time() > deadline:
                sys.exit("Prometheus never answered histogram_count for both jobs: native buckets not read")
            time.sleep(1)
        for template in QUERIES:
            mine, reference = query(base, template.format(job="moonp8s")), query(base, template.format(job="golang"))
            same = mine == reference and mine
            failures += not same
            print(f"{'ok  ' if same else 'FAIL'} {template.format(job='*')}: {mine}" + ("" if same else f" != {reference}"))
    finally:
        stop()
        golang.kill()
    return failures


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
