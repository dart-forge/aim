const routes = new Map();
for (let i = 1; i <= 100; i++) {
  const name = `item${String(i).padStart(3, '0')}`;
  routes.set(`/r/${name}`, name);
}
const text = (body) => new Response(body, { headers: { 'content-type': 'text/plain; charset=utf-8' } });
const json = (value) => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json; charset=utf-8' } });

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (request.method === 'GET' && path === '/') return text('Hello, World!');
    if (request.method === 'GET' && path.startsWith('/users/') && !path.slice(7).includes('/')) {
      return json({ id: path.slice(7), name: url.searchParams.get('name') });
    }
    if (request.method === 'POST' && path === '/json') return json(await request.json());
    if (request.method === 'GET' && routes.has(path)) return text(routes.get(path));
    return new Response('not found', { status: 404 });
  },
};
