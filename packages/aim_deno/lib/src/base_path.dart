/// Removes [basePath] from the front of [path].
///
/// Supabase Edge Functions serve each function under `/<function-name>` and
/// pass that segment through to the handler, so an app whose routes are
/// written as `/` never matches without this. Deno Deploy and Netlify Edge
/// serve at the root and pass `null`.
///
/// Only a whole leading segment is removed: `/my_api_v2` is left alone when
/// [basePath] is `my_api`.
String stripBasePath(String path, String? basePath) {
  if (basePath == null || basePath.isEmpty) return path;
  final prefix = basePath.startsWith('/') ? basePath : '/$basePath';
  if (path == prefix) return '/';
  if (!path.startsWith('$prefix/')) return path;
  final rest = path.substring(prefix.length);
  return rest.isEmpty ? '/' : rest;
}

/// [url] with [basePath] removed from the front of its path.
///
/// Everything else about the URI — query string, fragment, host — is kept.
Uri stripUriBasePath(Uri url, String? basePath) {
  final path = stripBasePath(url.path, basePath);
  return path == url.path ? url : url.replace(path: path);
}
