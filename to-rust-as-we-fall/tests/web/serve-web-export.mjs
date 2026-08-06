import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';

const port = Number(process.env.TRAWF_WEB_PORT ?? '41739');
const root = path.resolve(process.env.TRAWF_WEB_ROOT ?? 'build/web');
const mimeTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.pck', 'application/octet-stream'],
  ['.wasm', 'application/wasm'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.ogg', 'audio/ogg'],
]);

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', 'http://127.0.0.1');
    const relative = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html';
    const candidate = path.resolve(root, relative);
    const rootPrefix = `${root}${path.sep}`;
    if (candidate !== root && !candidate.startsWith(rootPrefix)) {
      response.writeHead(403).end('Forbidden');
      return;
    }
    const fileStat = await stat(candidate);
    if (!fileStat.isFile()) {
      response.writeHead(404).end('Not found');
      return;
    }
    response.writeHead(200, {
      'Content-Type': mimeTypes.get(path.extname(candidate).toLowerCase()) ?? 'application/octet-stream',
      'Content-Length': fileStat.size,
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
      'Cache-Control': 'no-store',
    });
    createReadStream(candidate).pipe(response);
  } catch (error) {
    response.writeHead(error?.code === 'ENOENT' ? 404 : 500).end(String(error));
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`[TRAWF-WEB] Serving ${root} at http://127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
