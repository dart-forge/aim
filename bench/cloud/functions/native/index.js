import { onRequest } from 'firebase-functions/v2/https';

const routes = new Map();
for (let i = 1; i <= 100; i++) {
  const name = `item${String(i).padStart(3, '0')}`;
  routes.set(`/r/${name}`, name);
}

export const benchNative = onRequest((req, res) => {
  const path = req.path;
  if (req.method === 'GET' && path === '/') return res.type('text/plain').send('Hello, World!');
  if (req.method === 'GET' && path.startsWith('/users/') && !path.slice(7).includes('/')) {
    return res.json({ id: path.slice(7), name: req.query.name ?? null });
  }
  if (req.method === 'POST' && path === '/json') return res.json(req.body);
  if (req.method === 'GET' && routes.has(path)) return res.type('text/plain').send(routes.get(path));
  res.status(404).send('not found');
});
