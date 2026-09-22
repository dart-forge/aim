let ready: Promise<void> | undefined;

async function init() {
  const { compile } = await import('./main.mjs');
  const bytes = await Deno.readFile(new URL('./main.wasm', import.meta.url));
  const compiled = await compile(bytes);
  const instance = await compiled.instantiate({});
  instance.invokeMain(); // runs Dart main(), which calls app.serveDeno()
}

Deno.serve(async (request: Request) => {
  ready ??= init();
  try {
    await ready;
  } catch (e) {
    ready = undefined; // let the next request retry initialisation
    throw e;
  }
  return (globalThis as any).__aimFetch(request);
});
