/// Shared pieces for running an Aim application on an edge runtime.
///
/// Pick the adapter for your runtime: `aim_workers` for Cloudflare workerd,
/// `aim_deno` for Deno-based runtimes such as Supabase Edge Functions.
library;

export 'package:aim_core/aim_core.dart';

export 'src/edge_context.dart' show EdgeContext;
export 'src/edge_env.dart' show EdgeEnv;
