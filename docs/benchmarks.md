---
title: Benchmarks - Aim
description: Measured request rates, latency, startup time, and memory for aim_server and four other Dart HTTP setups on one machine, with the conditions the numbers were taken under, plus cold start, warm latency, and upload size for Aim on Cloudflare Workers, Supabase Edge Functions, and Cloud Functions for Firebase.
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

## Edge and serverless runtimes

The same Aim app is deployed to Cloudflare Workers (compiled to
WebAssembly), Supabase Edge Functions (WebAssembly running on Deno), and
Cloud Functions for Firebase (a Dart binary running on Cloud Run), each
one next to a plain JS/TS baseline written directly against that
platform's own API (a `fetch` handler for Workers, `Deno.serve` for
Supabase, a Node `onRequest` handler for Cloud Functions). Both variants
answer the same four scenarios as the suite above. Everything below was
measured from one machine in Tokyo. Runtimes are not compared with each
other: Workers answers from the nearest Cloudflare colo, Supabase from
Southeast Asia (Singapore), and Cloud Functions from us-central1 — three
different regions from the measuring machine — so the numbers to read are
the Aim-versus-baseline pairs within one runtime, not one runtime against
another.

### What is measured

- **Cold start.** The time to first byte of the first request sent right
  after a fresh deployment, over a new DNS, TCP and TLS connection. Measured
  once per deploy cycle, over 5 deploy cycles, reported as a median. A
  404 returned while a brand-new route is still propagating is retried
  and counted; it was 0 here on every target.
- **Warm latency.** 100 sequential requests per scenario, concurrency 1,
  on a single kept-alive connection, reported as p50, p99, and min.
- **Upload size.** What each platform actually received: wrangler's own
  reported upload for Workers; `main.wasm` + `main.mjs` + `index.ts` for
  Supabase's Aim variant (`index.ts` alone for its native baseline, which
  has no wasm to ship); for Cloud Functions, the Dart AOT bundle
  directory for the Aim variant against the Node source files for the
  native baseline. The last pair is not the same kind of artifact — a
  compiled bundle versus source that the platform builds itself — and the
  numbers below say so rather than treat them as comparable.

### What is not measured

- Throughput: no load is put on any of these targets, which are shared
  cloud platforms, not a machine this suite owns.
- A comparison between runtimes: the three runtimes deploy to different
  regions, so a difference between, say, Workers and Cloud Functions may
  be network distance rather than the runtime.
- Database or other I/O-bound work: none of the six targets touch one.
- More than one measurement origin: every number here comes from one
  machine in Tokyo.
- Cold starts after idle eviction: every cold sample here follows a fresh
  deployment, not a platform evicting an idle instance later.

### Environment

- Measured from: Tokyo, office network
- workers region: nearest Cloudflare colo
- supabase region: Southeast Asia (Singapore)
- functions region: us-central1
- Tool versions: wrangler 4.138.0, supabase 2.111.0, firebase 15.30.0, node v26.8.2 (local CLI; the Cloud Function itself runs on the platform's Node 22 runtime)
- Dart: Dart SDK version: 3.13.3 (stable) (Tue Sep 1 01:07:17 2026 -0700) on "macos_arm64"
- Aim commit: 0ab0fcd
- 5 deploy cycles, 100 requests per scenario.
- Runtimes are not compared with each other: each region above is that runtime's own deployment region, and they differ from one runtime to the next, so a latency difference between runtimes may reflect network distance rather than the runtime itself.

### Results

#### Cold start

| Runtime | Variant | Cold, median (ms) | Warm right after, median (ms) | Difference (ms) | 404 retries before first answer (sum) |
|---|---|---:|---:|---:|---:|
| workers | aim | 101 | 28 | 74 | 0 |
| workers | native | 104 | 27 | 77 | 0 |
| supabase | aim | 209 | 130 | 79 | 0 |
| supabase | native | 192 | 107 | 85 | 0 |
| functions | aim | 235 | 174 | 62 | 0 |
| functions | native | 275 | 173 | 102 | 0 |

Warm latency: 100 sequential requests per scenario, concurrency 1, on a
kept-alive connection.

#### plaintext

| Runtime | Variant | p50 (ms) | p99 (ms) | min (ms) |
|---|---|---:|---:|---:|
| workers | aim | 24 | 123 | 17 |
| workers | native | 25 | 48 | 18 |
| supabase | aim | 131 | 254 | 47 |
| supabase | native | 105 | 170 | 38 |
| functions | aim | 175 | 245 | 159 |
| functions | native | 175 | 266 | 156 |

#### params_json

| Runtime | Variant | p50 (ms) | p99 (ms) | min (ms) |
|---|---|---:|---:|---:|
| workers | aim | 24 | 38 | 19 |
| workers | native | 26 | 69 | 20 |
| supabase | aim | 128 | 230 | 46 |
| supabase | native | 105 | 141 | 44 |
| functions | aim | 174 | 196 | 158 |
| functions | native | 189 | 246 | 167 |

#### post_json

| Runtime | Variant | p50 (ms) | p99 (ms) | min (ms) |
|---|---|---:|---:|---:|
| workers | aim | 26 | 50 | 20 |
| workers | native | 26 | 35 | 19 |
| supabase | aim | 124 | 160 | 38 |
| supabase | native | 99 | 129 | 43 |
| functions | aim | 171 | 205 | 156 |
| functions | native | 182 | 233 | 160 |

#### routes_100

| Runtime | Variant | p50 (ms) | p99 (ms) | min (ms) |
|---|---|---:|---:|---:|
| workers | aim | 23 | 45 | 18 |
| workers | native | 27 | 48 | 19 |
| supabase | aim | 98 | 204 | 42 |
| supabase | native | 88 | 139 | 36 |
| functions | aim | 171 | 187 | 158 |
| functions | native | 183 | 247 | 161 |

#### Upload size

| Runtime | Variant | Bytes | gzip | Note |
|---|---|---:|---:|---|
| workers | aim | 158956 | 61184 |  |
| workers | native | 1290 | 645 |  |
| supabase | aim | 156608 | 60795 |  |
| supabase | native | 1327 | 668 |  |
| functions | aim | 7558216 | ? | AOT bundle |
| functions | native | 1115 | 668 | source only |

### Reading the numbers

- The "Cold" column is the first request after a deployment, and on
  every one of the six targets it exceeds the warm median right after by
  60–102 ms. That difference is close to the cost of a new TCP and TLS
  connection from Tokyo, so at this resolution the start-up cost of the
  WebAssembly or Dart instance is not separable from the connection cost.
- On Cloud Run, a deployment starts an instance to check that it listens,
  so the first request after a deployment does not measure a
  scale-from-zero start.
- The first cycle of each target was often higher than the later four;
  the committed JSON keeps all five.
- Warm p50 is dominated by round-trip time from Tokyo: about 25 ms to the
  nearest Cloudflare colo, 88–131 ms to Singapore, 170–190 ms to
  us-central1.
- Warm p50 within each runtime, Aim next to its baseline (ms):

  | Runtime | Scenario | Aim | Baseline |
  |---|---|---:|---:|
  | Workers | plaintext | 24 | 25 |
  | Workers | params_json | 24 | 26 |
  | Workers | post_json | 26 | 26 |
  | Workers | routes_100 | 23 | 27 |
  | Supabase | plaintext | 131 | 105 |
  | Supabase | params_json | 128 | 105 |
  | Supabase | post_json | 124 | 99 |
  | Supabase | routes_100 | 98 | 88 |
  | Cloud Functions | plaintext | 175 | 175 |
  | Cloud Functions | params_json | 174 | 189 |
  | Cloud Functions | post_json | 171 | 182 |
  | Cloud Functions | routes_100 | 171 | 183 |
- Upload sizes (KB here means 1000 bytes): the WebAssembly build is 159 KB
  (61 KB gzipped) for Workers and 157 KB (61 KB gzipped) for Supabase,
  against 1.3 KB of JavaScript for each native baseline; the Dart AOT
  bundle for Cloud Functions is 7.6 MB against 1.1 KB of Node source, and
  the Node deployment additionally pulls its dependencies on the
  platform, so that last pair is not the same kind of number.
- The native baselines route the 100 static routes with a `Map`, so
  `routes_100` on a native baseline measures no router. Both Supabase
  functions were deployed with JWT verification off. Both Cloud Functions
  are public HTTP endpoints. All other platform settings are defaults.

### Reproduce

Prerequisites:

- [`wrangler`](https://developers.cloudflare.com/workers/wrangler/),
  logged in.
- The [Supabase CLI](https://supabase.com/docs/guides/cli), logged in,
  with Docker running.
- [`firebase-tools`](https://firebase.google.com/docs/cli), logged in, on
  a Blaze-plan project, with the `dartfunctions` experiment enabled
  (`firebase experiments:enable dartfunctions`).
- Node 22 as the Cloud Functions runtime for the native baseline.
- `bench/cloud/config.yaml`, copied from `bench/cloud/config.example.yaml`
  and filled in with real values.

```bash
cd bench/runner
dart pub get
dart run bin/bench.dart cloud verify                        # every target must answer identically
dart run bin/bench.dart cloud run --label <short-description>
dart run bin/bench.dart cloud render ../results/cloud-<date>-<label>.json
```

Results files live under `bench/results/`, in the same shape
`cloud render` reads back. The full cloud suite, including the fairness
rules and what is never recorded, is on
[GitHub](https://github.com/dart-forge/aim/tree/main/bench).
