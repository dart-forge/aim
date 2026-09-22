---
layout: home
title: Aim - Modular Dart Ecosystem
titleTemplate: Server, Database, ORM - on the Dart VM, Cloudflare Workers, and Cloud Functions
description: A modular ecosystem for Dart. Web server, database, ORM, and CLI tools as independent packages. Runs on the Dart VM, on Cloudflare Workers via WebAssembly, and on Cloud Functions for Firebase.

hero:
  name: "Aim"
  text: "Modular ecosystem for Dart"
  tagline: Web server, database, ORM - on the Dart VM, Cloudflare Workers, and Cloud Functions
  actions:
    - theme: brand
      text: Server
      link: /server/
    - theme: alt
      text: Database
      link: /database/
    - theme: alt
      text: CLI
      link: /cli/

features:
  - icon: 🌐
    title: Web Server
    details: Lightweight, fast web framework with Context API, routing, middleware, and authentication.
    link: /server/
    linkText: Get Started
  - icon: 🗄️
    title: Database
    details: Native PostgreSQL driver with SSL/TLS, transactions, and type-safe ORM. Works independently without web server.
    link: /database/
    linkText: Get Started
  - icon: ☁️
    title: Cloudflare Workers
    details: Compile the same app to WebAssembly and run it on Cloudflare Workers. Bindings via c.env, request metadata via c.cf.
    link: /server/workers
    linkText: Get Started
  - icon: 🟢
    title: Supabase Edge Functions
    details: Compile the same app to WebAssembly and run it as a Supabase Edge Function on Deno. Verified against a local Supabase stack; a production deploy is not yet verified.
    link: /server/supabase
    linkText: Get Started
  - icon: 🔥
    title: Cloud Functions
    details: Run the same app as an HTTP function on Cloud Functions for Firebase. The Firebase CLI compiles and deploys it; aim dev runs it in the emulator. Dart support is experimental.
    link: /server/functions
    linkText: Get Started
  - icon: ⚡
    title: CLI Tools
    details: Project scaffolding, hot reload, production builds, wasm builds for Cloudflare Workers, and the Firebase emulator for Cloud Functions.
    link: /cli/
    linkText: Get Started
  - icon: 🧩
    title: Modular
    details: Use what you need. Each package works independently - add only what your project requires.
  - icon: ✅
    title: Validation
    details: Declare a request's shape as a procedure and read it back with static types - no cast, no code generation.
    link: /server/validation
    linkText: Get Started
---
