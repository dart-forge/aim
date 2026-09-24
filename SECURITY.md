# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Report it privately through GitHub's vulnerability reporting form:

https://github.com/dart-forge/aim/security/advisories/new

Include, as far as you can:

- the package(s) and version(s) affected (for example `aim_server_jwt 0.4.0`)
- steps to reproduce, or a proof of concept
- the impact you expect (what an attacker gains, and under which conditions)
- whether the issue is already public anywhere

If you cannot use the form, open a public issue that says only that you
have a security report to make, without any details, and a maintainer
will reach out to you.

## What to expect

Aim is maintained by a single person, so the numbers below are targets,
not guarantees.

- You should get an acknowledgement within **14 days**.
- Confirmed issues are fixed in the current minor release line and
  published to pub.dev. Timing depends on severity and on how much of
  the framework the fix touches.
- The advisory is published after the fixed versions are on pub.dev,
  and it credits the reporter unless you ask otherwise.
- If a report is not accepted as a vulnerability, you get a reply saying
  why. Where it still describes a real bug, it moves to a public issue
  with your permission.

## Supported versions

Aim is pre-1.0. Every package in the repository shares one version
number, and only the **latest minor release line** receives security
fixes.

| Version | Supported |
| ------- | --------- |
| 0.4.x   | Yes       |
| < 0.4   | No        |

Upgrading is the fix for older lines.

## Scope

In scope: every published package under `packages/`, including the
runtime adapters (`aim_server`, `aim_workers`, `aim_deno`,
`aim_functions`), the `aim_server_*` middleware, the database drivers,
the ORM, and `aim_cli`.

Out of scope:

- Vulnerabilities in third-party dependencies that Aim does not
  misuse. Report those upstream; a report here is still welcome if Aim
  needs to bump a version or change how it calls the dependency.
- The `examples/` and `bench/` directories and the documentation site.
  They are not published and not meant for production use.
- Limitations that are already documented on the
  [Component Status](https://aim-dart.dev/status) page, such
  as `aim_server_jwt` supporting HS256 only, or the absence of a
  dedicated security audit. Those are known gaps, not undisclosed
  vulnerabilities; an issue or pull request is the right place for them.
- Findings that require an attacker to already control the server, its
  configuration, or its database credentials.
