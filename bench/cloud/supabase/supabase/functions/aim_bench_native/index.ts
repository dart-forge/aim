// Supabase hands the handler a path of `/aim_bench_native/...` — the
// function-name segment only, without `/functions/v1` — so that's what
// gets stripped here.
const base = '/aim_bench_native';
const routes = new Map<string, string>();
for (let i = 1; i <= 100; i++) {
  const name = `item${String(i).padStart(3, '0')}`;
  routes.set(`/r/${name}`, name);
}
const text = (body: string) => new Response(body, { headers: { 'content-type': 'text/plain; charset=utf-8' } });
const json = (value: unknown) => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json; charset=utf-8' } });

Deno.serve(async (request: Request) => {
  const url = new URL(request.url);
  let path = url.pathname;
  if (path === base) {
    path = '/';
  } else if (path.startsWith(base + '/')) {
    path = path.slice(base.length);
  }
  if (request.method === 'GET' && path === '/') return text('Hello, World!');
  if (request.method === 'GET' && path.startsWith('/users/') && !path.slice(7).includes('/')) {
    return json({ id: path.slice(7), name: url.searchParams.get('name') });
  }
  if (request.method === 'POST' && path === '/json') return json(await request.json());
  if (request.method === 'GET' && routes.has(path)) return text(routes.get(path));
  return new Response('not found', { status: 404 });
});
