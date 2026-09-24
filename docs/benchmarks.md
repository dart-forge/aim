---
title: Benchmarks - Aim
description: Measured request rates, latency, startup time, and memory for aim_server and four other Dart HTTP setups on one machine, with the conditions the numbers were taken under.
head:
  - - meta
    - name: keywords
      content: Aim benchmark, Dart web framework benchmark, aim_server performance, shelf benchmark, dart_frog benchmark, relic benchmark
---

# Benchmarks

## What is measured

Five apps — a bare `dart:io` `HttpServer`, `aim_server`, `shelf` +
`shelf_router`, `relic`, and `dart_frog` — answer the same four scenarios.
Every app is a `dart compile exe` binary, runs as a single isolate, adds no
middleware or logging, and keeps its framework's default configuration.
Load comes from `oha` over loopback on the same machine. Before any app is
measured, it must answer all four scenarios identically to the others.

| Scenario | Request | Response | What it exercises |
|---|---|---|---|
| `plaintext` | `GET /` | `Hello, World!` (text) | Baseline request/response overhead with no parsing. |
| `params_json` | `GET /users/42?name=aim` | `{"id":"42","name":"aim"}` (JSON) | Path parameter extraction, query string parsing, JSON encoding. |
| `post_json` | `POST /json` with a JSON body | the same JSON, echoed back | Request body reading and JSON decoding, on top of encoding. |
| `routes_100` | `GET /r/item100` | `item100` (text) | Router lookup cost with 100 registered static routes (`/r/item001` … `/r/item100`) instead of one. |

## What is not measured

- TLS termination.
- A database or other I/O-bound work.
- Real network conditions — every run is against `127.0.0.1`.
- More than one isolate.
- Large request or response bodies.
- Anything else a real application spends its time on.

These numbers say nothing about database-bound applications. A single
machine on a single day is one data point, not a ranking.

## Environment

- Date: 2026-09-24
- Machine: Apple M5 Pro, 15 cores, 48 GiB, macOS 26.5.1 (arm64)
- Dart: Dart SDK version: 3.13.3 (stable) (Tue Sep 1 01:07:17 2026 -0700) on "macos_arm64"
- Aim commit: e845d62
- Load generator: oha 1.16.0, 64 connections, 10 s per run, median of 5 runs
- Every app is a `dart compile exe` binary, one isolate, no middleware; the load generator connects to 127.0.0.1 (dart_frog's generated server listens on all interfaces, the others on loopback only).
- Startup is the median of three launches after one discarded launch; the first launch of a freshly compiled binary pays a one-time first-execution cost on macOS and is not what a redeploy sees.

## Versions

| App | Packages |
|---|---|
| dart_io | dart:io only |
| aim | aim_server 0.4.0 (path), aim_core 0.4.0 (path) |
| shelf_router | shelf 1.4.2, shelf_router 1.1.4 |
| relic | relic 1.2.0, relic_core 1.2.0, relic_io 1.2.0 |
| dart_frog | dart_frog 1.2.6, shelf 1.4.2 |

## Results

### plaintext

`GET /`

| App | Requests/s | p50 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dart_io | 21,867 | 2.66 | 5.18 |
| aim | 20,303 | 2.89 | 5.39 |
| shelf_router | 19,683 | 2.97 | 5.18 |
| relic | 19,281 | 3.05 | 5.57 |
| dart_frog | 17,247 | 3.39 | 5.96 |

### params_json

`GET /users/42?name=aim`

| App | Requests/s | p50 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dart_io | 21,917 | 2.67 | 4.87 |
| aim | 19,777 | 3.02 | 5.62 |
| shelf_router | 18,087 | 3.24 | 5.45 |
| relic | 18,801 | 3.15 | 5.42 |
| dart_frog | 13,943 | 4.22 | 6.93 |

### post_json

`POST /json`

| App | Requests/s | p50 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dart_io | 21,049 | 2.79 | 4.84 |
| aim | 18,980 | 3.09 | 5.70 |
| shelf_router | 17,189 | 3.46 | 5.86 |
| relic | 17,419 | 3.38 | 5.78 |
| dart_frog | 14,796 | 4.01 | 6.77 |

### routes_100

`GET /r/item100`

| App | Requests/s | p50 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dart_io | 22,505 | 2.60 | 4.92 |
| aim | 20,022 | 2.91 | 5.30 |
| shelf_router | 15,889 | 3.74 | 6.22 |
| relic | 19,388 | 3.03 | 5.58 |
| dart_frog | 7,243 | 8.46 | 12.63 |

### Footprint

| App | Startup to first 200, warm binary (ms) | Memory after load (MiB) | Binary (MiB) |
|---|---:|---:|---:|
| dart_io | 18 | 39 | 5.8 |
| aim | 18 | 39 | 5.9 |
| shelf_router | 18 | 22 | 6.4 |
| relic | 17 | 42 | 7.6 |
| dart_frog | 17 | 40 | 6.5 |

## Reading the numbers

- Requests/s and latency are the median of five 10-second runs at 64
  connections after a 3-second warm-up; the committed JSON keeps all five
  runs.
- In this run every app/scenario stayed within 10% of its median except
  dart_io on plaintext (12%).
- Startup is the median of three launches after one discarded launch; the
  first launch of a freshly compiled binary pays a one-time first-execution
  cost on macOS and is excluded.
- Memory is the physical footprint reported by `footprint` (macOS refuses
  `ps`'s rss column), reported in whole MiB.
- dart_frog's generated server listens on all interfaces while the other
  four bind loopback (defaults kept; the load generator always connects to
  127.0.0.1).
- dart_frog's `routes_100` figure reflects that its generated server builds
  the `/r/` directory's router on every request (its default, kept).
- Apps run in a fixed order (dart_io, aim, shelf_router, relic, dart_frog),
  so thermal drift over the ~25 minutes would affect later apps more.

## What this says about Aim's router

Aim's router is a linear scan of registered routes with the first match
winning. In this run, aim's `routes_100` median of 20,022 requests/s (100
static routes, last one requested) was about 1% below its `plaintext`
median of 20,303 requests/s. Over bare dart:io, aim's median requests/s was
7% lower on `plaintext` and 10% lower on `params_json` and `post_json`.
Run-to-run spread in this data is 2–12%, so differences of a few percent
are within noise.

## Reproduce

Prerequisites:

- Dart 3.13 or newer.
- [`oha`](https://github.com/hatoo/oha) 1.16 or newer: `brew install oha`.
- macOS — the runner reads machine info with `sysctl`/`sw_vers` and reads a
  running app's memory with `footprint`.

```bash
cd bench/runner
dart pub get
dart run bin/bench.dart verify        # every app must answer identically
dart run bin/bench.dart run --label <short-description>  # e.g. m5-pro, not the hostname
dart run bin/bench.dart render ../results/<date>-<label>.json
```

Results files, with all runs kept (not just the median), live under
`bench/results/`. The full suite, including the fairness rules and how to
add another app, is on
[GitHub](https://github.com/dart-forge/aim/tree/main/bench).
