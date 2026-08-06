#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { createReadStream } from 'node:fs';
import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

function parseArgs(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error(`Invalid argument near '${key ?? '<end>'}'. Expected --name value pairs.`);
    }
    values.set(key.slice(2), value);
  }
  return values;
}

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

function startStaticServer(root) {
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
      const statusCode = error?.code === 'ENOENT' ? 404 : 500;
      response.writeHead(statusCode).end(statusCode === 404 ? 'Not found' : String(error));
    }
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

async function waitUntil(predicate, timeoutMs, label, intervalMs = 200) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const result = await predicate();
      if (result) return result;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  throw new Error(`Timed out waiting for ${label}${lastError ? `: ${lastError.message}` : ''}`);
}

class CdpSession {
  constructor(url) {
    if (typeof WebSocket === 'undefined') {
      throw new Error('Node.js 22 or newer is required (global WebSocket is unavailable).');
    }
    this.socket = new WebSocket(url);
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
  }

  async open() {
    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, { once: true });
      this.socket.addEventListener('error', () => reject(new Error('CDP WebSocket connection failed.')), { once: true });
    });
    this.socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id !== undefined) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(`${message.error.message} (${message.error.code})`));
        else pending.resolve(message.result ?? {});
        return;
      }
      const callbacks = this.listeners.get(message.method) ?? [];
      for (const callback of callbacks) callback(message.params ?? {});
    });
  }

  on(method, callback) {
    const callbacks = this.listeners.get(method) ?? [];
    callbacks.push(callback);
    this.listeners.set(method, callbacks);
  }

  send(method, params = {}) {
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
    this.socket.send(JSON.stringify({ id, method, params }));
    return promise;
  }

  close() {
    try { this.socket.close(); } catch { /* Browser teardown owns the process. */ }
  }
}

function formatRemoteValue(value) {
  if (Object.hasOwn(value, 'value')) return String(value.value);
  return value.description ?? value.type ?? '<unknown>';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.get('root') ?? '');
  const browserPath = path.resolve(args.get('browser') ?? '');
  const timeoutMs = Number(args.get('timeout-seconds') ?? '180') * 1000;
  const screenshotPath = path.resolve(args.get('screenshot') ?? path.join(root, 'web-smoke.png'));
  const reportPath = path.resolve(args.get('report') ?? path.join(root, 'web-smoke.json'));

  await stat(path.join(root, 'index.html'));
  await stat(browserPath);
  const server = await startStaticServer(root);
  const address = server.address();
  const gameUrl = `http://127.0.0.1:${address.port}/index.html`;
  const profileDirectory = await mkdtemp(path.join(os.tmpdir(), 'trawf-web-smoke-'));
  let browser;
  let cdp;
  const failures = [];

  try {
    browser = spawn(browserPath, [
      '--headless=new',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist',
      '--autoplay-policy=no-user-gesture-required',
      '--remote-debugging-port=0',
      `--user-data-dir=${profileDirectory}`,
      '--window-size=1280,720',
      'about:blank',
    ], { stdio: ['ignore', 'pipe', 'pipe'] });

    let browserStderr = '';
    browser.stderr.on('data', (chunk) => { browserStderr += chunk.toString(); });
    const devToolsFile = path.join(profileDirectory, 'DevToolsActivePort');
    const devToolsContents = await waitUntil(async () => {
      const text = await readFile(devToolsFile, 'utf8');
      return text.includes('\n') ? text : null;
    }, 15000, 'Chromium DevTools endpoint');
    const debugPort = Number(devToolsContents.split(/\r?\n/)[0]);
    const target = await waitUntil(async () => {
      const response = await fetch(`http://127.0.0.1:${debugPort}/json/list`);
      const targets = await response.json();
      return targets.find((entry) => entry.type === 'page' && entry.webSocketDebuggerUrl);
    }, 10000, 'Chromium page target');

    cdp = new CdpSession(target.webSocketDebuggerUrl);
    await cdp.open();
    cdp.on('Runtime.exceptionThrown', ({ exceptionDetails }) => {
      failures.push(`Uncaught exception: ${exceptionDetails?.exception?.description ?? exceptionDetails?.text ?? 'unknown'}`);
    });
    cdp.on('Runtime.consoleAPICalled', ({ type, args: values = [] }) => {
      if (type === 'error' || type === 'assert') {
        failures.push(`Console ${type}: ${values.map(formatRemoteValue).join(' ')}`);
      }
    });
    cdp.on('Log.entryAdded', ({ entry }) => {
      if (entry?.level === 'error') failures.push(`Browser log: ${entry.text}`);
    });
    cdp.on('Network.loadingFailed', ({ errorText, canceled, type }) => {
      if (!canceled) failures.push(`Network ${type ?? 'resource'} failed: ${errorText}`);
    });

    await Promise.all([
      cdp.send('Page.enable'),
      cdp.send('Runtime.enable'),
      cdp.send('Log.enable'),
      cdp.send('Network.enable'),
    ]);
    await cdp.send('Page.navigate', { url: gameUrl });

    const readyState = await waitUntil(async () => {
      const evaluation = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const canvas = document.querySelector('canvas');
          const status = document.querySelector('#status');
          return {
            ready: Boolean(canvas && !status && canvas.width > 0 && canvas.height > 0 && globalThis.crossOriginIsolated),
            canvasWidth: canvas?.width ?? 0,
            canvasHeight: canvas?.height ?? 0,
            crossOriginIsolated: globalThis.crossOriginIsolated,
            statusText: status?.textContent?.trim() ?? ''
          };
        })()`,
        returnByValue: true,
      });
      const value = evaluation.result?.value;
      return value?.ready ? value : null;
    }, timeoutMs, 'Godot canvas boot (the loading overlay must disappear)', 500);

    // A real browser input event focuses and clicks the exported canvas. This is a
    // platform smoke, not a replacement for the level-specific player contract.
    await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 640, y: 360 });
    await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 640, y: 360, button: 'left', clickCount: 1 });
    await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 640, y: 360, button: 'left', clickCount: 1 });
    await new Promise((resolve) => setTimeout(resolve, 1500));

    const screenshot = await cdp.send('Page.captureScreenshot', { format: 'png', fromSurface: true });
    await writeFile(screenshotPath, Buffer.from(screenshot.data, 'base64'));

    // Give asynchronous page/engine errors a final chance to surface.
    await new Promise((resolve) => setTimeout(resolve, 500));
    if (browser.exitCode !== null) {
      failures.push(`Chromium exited early with code ${browser.exitCode}: ${browserStderr.slice(-2000)}`);
    }
    if (failures.length > 0) {
      throw new Error(failures.join('\n'));
    }

    const report = {
      ok: true,
      url: gameUrl,
      canvas: { width: readyState.canvasWidth, height: readyState.canvasHeight },
      crossOriginIsolated: readyState.crossOriginIsolated,
      screenshot: screenshotPath,
      failures: [],
    };
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    console.log(`[WEB-SMOKE] PASS: Godot canvas booted at ${readyState.canvasWidth}x${readyState.canvasHeight}, accepted browser input, and emitted no page errors.`);
    console.log(`[WEB-SMOKE] Screenshot: ${screenshotPath}`);
  } catch (error) {
    const report = { ok: false, url: gameUrl, failures: [...failures, error.message] };
    try { await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`); } catch { /* Preserve the primary failure. */ }
    throw error;
  } finally {
    cdp?.close();
    if (browser && browser.exitCode === null) {
      const browserExited = new Promise((resolve) => browser.once('exit', resolve));
      browser.kill();
      await Promise.race([
        browserExited,
        new Promise((resolve) => setTimeout(resolve, 3000)),
      ]);
      if (browser.exitCode === null) {
        browser.kill('SIGKILL');
        await Promise.race([
          browserExited,
          new Promise((resolve) => setTimeout(resolve, 3000)),
        ]);
      }
    }
    await new Promise((resolve) => server.close(resolve));
    await rm(profileDirectory, { recursive: true, force: true, maxRetries: 8, retryDelay: 250 });
  }
}

main().catch((error) => {
  console.error(`[WEB-SMOKE] FAIL: ${error.stack ?? error}`);
  process.exitCode = 1;
});
