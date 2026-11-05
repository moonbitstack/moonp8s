#!/usr/bin/env python3
"""Differential test of the multiprocess directory against prometheus_client.

Two directions, both over real files:

  ours -> theirs   the MoonBit example writes a directory as three worker
                   processes; prometheus_client's MultiProcessCollector reads the
                   same files and renders them; the two texts are compared.
  theirs -> ours   prometheus_client writes a directory as three worker
                   processes; the MoonBit example reads it; the two texts are
                   compared.

The comparison is byte for byte on every line once the sample lines of a family
are sorted: the two writers agree on the values, the headers, and the spelling of
every number, but they emit the series of one family in different orders
(prometheus_client's merge rebuilds a histogram's samples as sum, buckets, count,
in the order it first met them). Series order carries no meaning in either
format, so the comparison is on content.

Usage: check_multiprocess.py --binary <path to the 09-multiprocess executable>
"""

import argparse
import glob
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def check_client():
    try:
        import prometheus_client  # noqa: F401
    except ImportError:
        sys.exit("prometheus_client is not installed; pip install prometheus_client")
    from prometheus_client.multiprocess import MultiProcessCollector
    from prometheus_client.registry import CollectorRegistry

    return MultiProcessCollector.merge, CollectorRegistry


class Directory:
    """A registry whose one collector is a directory of worker files."""

    def __init__(self, path, merge):
        self.path = path
        self.merge = merge

    def collect(self):
        return self.merge(sorted(glob.glob(os.path.join(self.path, "*.db"))))


def render_with_client(path):
    from prometheus_client.exposition import generate_latest

    merge, collector_registry = check_client()
    registry = collector_registry()
    registry.register(Directory(path, merge))
    return generate_latest(registry).decode("utf-8")


def blocks(text):
    """Split an exposition into (header lines, sorted sample lines) per family."""
    families = []
    header = []
    samples = []
    for line in text.split("\n"):
        if line == "":
            continue
        if line.startswith("#"):
            name = line.split(" ")[2] if line.count(" ") >= 2 else ""
            if samples and header and name and name != header[0]:
                families.append((tuple(header), tuple(sorted(samples))))
                header = []
                samples = []
            header.append(line)
        else:
            samples.append(line)
    if header or samples:
        families.append((tuple(header), tuple(sorted(samples))))
    return families


def normalize(text):
    # prometheus_client writes `# EOF` only for OpenMetrics; neither side does
    # here, but strip a trailing newline difference all the same.
    return "\n".join(
        "\n".join(headers) + "\n" + "\n".join(samples)
        for headers, samples in blocks(text)
    ).strip()


def compare(label, ours, theirs):
    families = len(blocks(ours))
    samples = sum(len(s) for _, s in blocks(ours))
    if ours == theirs:
        print(f"  {label}: {families} families, {samples} samples, byte for byte")
        return True
    if normalize(ours) == normalize(theirs):
        print(
            f"  {label}: {families} families, {samples} samples, identical; "
            "series of a family in a different order"
        )
        return True
    print(f"  {label}: DIFFERENT")
    ours_blocks = blocks(ours)
    theirs_blocks = blocks(theirs)
    for i in range(max(len(ours_blocks), len(theirs_blocks))):
        a = ours_blocks[i] if i < len(ours_blocks) else None
        b = theirs_blocks[i] if i < len(theirs_blocks) else None
        if a != b:
            print(f"    family {i}:")
            print(f"      ours:   {a}")
            print(f"      theirs: {b}")
            break
    return False


def run(binary, args, env=None):
    result = subprocess.run([binary] + args, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        sys.exit(f"{binary} {' '.join(args)} failed:\n{result.stderr}")
    return result.stdout.replace("\r\n", "\n")


def body(binary, directory, out, fmt="text"):
    """The bytes a /metrics would send, written by the library itself."""
    args = ["--dir", directory, "--out", out]
    if fmt != "text":
        args += ["--format", fmt]
    run(binary, args)
    with open(out, encoding="utf-8", newline="") as handle:
        return handle.read()


def worker(path):
    """One prometheus_client worker process, writing its own file."""
    from prometheus_client import Counter, Gauge, Histogram, Summary

    pid = os.getpid()
    orders = Counter("py_orders", "Py orders, by code.", ["code"])
    orders.labels("200").inc(pid * 2)
    orders.labels("500").inc(1)
    depth = Gauge("py_depth", "Py depth.", multiprocess_mode="livesum")
    depth.set(pid * 1.5)
    latency = Histogram(
        "py_latency_seconds", "Py latency.", buckets=[0.1, 0.5, 1.0]
    )
    latency.observe(0.05 * pid)
    latency.observe(0.7)
    size = Summary("py_size_bytes", "Py size.")
    size.observe(100.0 * pid)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", help="the 09-multiprocess executable")
    parser.add_argument("--worker", action="store_true")
    args = parser.parse_args()

    if args.worker:
        worker(os.environ["PROMETHEUS_MULTIPROC_DIR"])
        return
    if not args.binary:
        parser.error("--binary is required")

    ok = True
    with tempfile.TemporaryDirectory(prefix="moonp8s-multiproc-") as work:
        ours_dir = os.path.join(work, "ours")
        os.mkdir(ours_dir)
        for pid in (1, 2, 3):
            run(args.binary, ["--dir", ours_dir, "--pid", str(pid)])
        ours = body(args.binary, ours_dir, os.path.join(work, "ours.txt"))
        theirs = render_with_client(ours_dir)
        print("the MoonBit workers, read by prometheus_client:")
        ok = compare("text", ours, theirs) and ok

        their_dir = os.path.join(work, "theirs")
        os.mkdir(their_dir)
        env = dict(os.environ, PROMETHEUS_MULTIPROC_DIR=their_dir)
        for _ in range(3):
            subprocess.run(
                [sys.executable, os.path.abspath(__file__), "--worker"],
                check=True,
                env=env,
            )
        theirs = render_with_client(their_dir)
        ours = body(args.binary, their_dir, os.path.join(work, "theirs.txt"))
        print("the prometheus_client workers, read by this library:")
        ok = compare("text", ours, theirs) and ok

    if not ok:
        sys.exit("the two implementations disagree")
    print("both directions agree")


if __name__ == "__main__":
    main()
