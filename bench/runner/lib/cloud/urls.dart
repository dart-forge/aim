/// Appends [pathAndQuery] (as written in a scenario, starting with '/') to
/// [base], keeping any path the base already has. `Uri.resolve` would drop
/// it, which is wrong for a Supabase function served under
/// `/functions/v1/<name>`.
Uri joinPath(Uri base, String pathAndQuery) {
  final q = pathAndQuery.indexOf('?');
  final path = q < 0 ? pathAndQuery : pathAndQuery.substring(0, q);
  final query = q < 0 ? null : pathAndQuery.substring(q + 1);
  final basePath = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
  return base.replace(path: '$basePath$path', query: query);
}
