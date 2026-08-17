#!/usr/bin/env python3
"""Independent MJPEG receiver used by evaluators; do not distribute to candidates."""

import argparse
import hashlib
import statistics
import time
import urllib.request


def percentile(values, fraction):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round((len(ordered) - 1) * fraction)))
    return ordered[index]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://192.168.4.1:81/stream")
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--min-fps", type=float, default=20.0)
    parser.add_argument("--max-p95-ms", type=float, default=100.0)
    parser.add_argument("--min-unique-ratio", type=float, default=0.50)
    args = parser.parse_args()

    request = urllib.request.Request(args.url, headers={"Cache-Control": "no-cache"})
    started = time.perf_counter()
    deadline = started + args.seconds
    timestamps = []
    hashes = []
    total_bytes = 0
    buffer = bytearray()

    with urllib.request.urlopen(request, timeout=3.0) as response:
        while time.perf_counter() < deadline:
            chunk = response.read(16384)
            if not chunk:
                break
            total_bytes += len(chunk)
            buffer.extend(chunk)
            while True:
                start = buffer.find(b"\xff\xd8")
                if start < 0:
                    if len(buffer) > 1:
                        del buffer[:-1]
                    break
                end = buffer.find(b"\xff\xd9", start + 2)
                if end < 0:
                    if start:
                        del buffer[:start]
                    break
                frame = bytes(buffer[start : end + 2])
                del buffer[: end + 2]
                timestamps.append(time.perf_counter())
                hashes.append(hashlib.blake2s(frame, digest_size=8).digest())

    elapsed = max(0.001, time.perf_counter() - started)
    intervals = [(b - a) * 1000.0 for a, b in zip(timestamps, timestamps[1:])]
    fps = len(timestamps) / elapsed
    median_ms = statistics.median(intervals) if intervals else 0.0
    p95_ms = percentile(intervals, 0.95)
    max_ms = max(intervals, default=0.0)
    unique_ratio = len(set(hashes)) / max(1, len(hashes))
    mbps = total_bytes * 8.0 / elapsed / 1_000_000.0

    passed = (
        fps >= args.min_fps
        and p95_ms <= args.max_p95_ms
        and unique_ratio >= args.min_unique_ratio
    )
    print(f"frames={len(timestamps)} elapsed={elapsed:.2f}s fps={fps:.2f}")
    print(f"interval median={median_ms:.1f}ms p95={p95_ms:.1f}ms max={max_ms:.1f}ms")
    print(f"throughput={mbps:.2f}Mbps unique_ratio={unique_ratio:.3f}")
    print("PASS" if passed else "FAIL")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()

