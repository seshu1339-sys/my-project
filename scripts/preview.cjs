// Local-only preview of the compiled Flutter web build.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../build/web');
const mime = {'.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf'};
http.createServer((req, res) => {
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400).end(); return; }
  const file = path.resolve(root, '.' + pathname, pathname.endsWith('/') ? 'index.html' : '');
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  // SPA fallback, mirroring build/web/.htaccess's production rewrite: any
  // path that isn't a real file (e.g. the admin route /jyothi9) serves
  // index.html instead of 404ing, so the Flutter app's own client-side
  // Uri.base.path check actually runs against that path.
  fs.readFile(file, (error, data) => {
    if (error) {
      fs.readFile(path.join(root, 'index.html'), (fallbackError, fallbackData) => {
        if (fallbackError) { res.writeHead(404).end('Not found'); return; }
        res.writeHead(200, {'Content-Type': 'text/html'}); res.end(fallbackData);
      });
      return;
    }
    res.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream'}); res.end(data);
  });
}).listen(8090, '127.0.0.1', () => console.log('Preview: http://127.0.0.1:8090'));
