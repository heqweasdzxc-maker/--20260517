import fs from 'node:fs';
import path from 'node:path';

const distDir = path.resolve(process.argv[2] || 'frontend/dist');
const entryFile = path.join(distDir, 'index.html');

if (!fs.existsSync(entryFile)) {
  console.error(`ERROR: missing frontend entry: ${entryFile}`);
  process.exit(2);
}

const normalize = (value) => value.split(path.sep).join('/').replace(/^\.\//, '');
const queue = ['index.html'];
const visited = new Set();
const missing = new Set();

function resolveReference(fromFile, reference) {
  const clean = reference.split(/[?#]/, 1)[0];
  if (clean.startsWith('/assets/')) return clean.slice(1);
  if (clean.startsWith('assets/')) return clean;
  if (clean.startsWith('./') || clean.startsWith('../')) {
    return normalize(path.posix.normalize(path.posix.join(path.posix.dirname(fromFile), clean)));
  }
  return null;
}

function referencesIn(content) {
  const references = new Set();
  const patterns = [
    /(?:src|href)=["']([^"']+)["']/g,
    /(?:from\s*|import\s*\(|new\s+URL\s*\()\s*["'`]([^"'`]+)["'`]/g,
    /["'`](\/?assets\/[A-Za-z0-9_./-]+\.(?:js|css|wasm|json|png|jpe?g|svg|webp|woff2?))["'`]/g,
    /url\(\s*["']?([^"')]+)["']?\s*\)/g,
  ];

  for (const pattern of patterns) {
    for (const match of content.matchAll(pattern)) references.add(match[1]);
  }
  return references;
}

while (queue.length) {
  const relative = queue.shift();
  if (!relative || visited.has(relative)) continue;
  visited.add(relative);

  const absolute = path.join(distDir, ...relative.split('/'));
  if (!fs.existsSync(absolute)) {
    missing.add(relative);
    continue;
  }

  if (!/\.(?:html|js|css)$/.test(relative)) continue;
  const content = fs.readFileSync(absolute, 'utf8');
  for (const reference of referencesIn(content)) {
    const resolved = resolveReference(relative, reference);
    if (!resolved) continue;
    const target = path.join(distDir, ...resolved.split('/'));
    if (!fs.existsSync(target)) missing.add(resolved);
    else if (!visited.has(resolved)) queue.push(resolved);
  }
}

if (missing.size) {
  console.error(`ERROR: ${missing.size} referenced frontend assets are missing:`);
  for (const file of [...missing].sort()) console.error(`  ${file}`);
  process.exit(1);
}

console.log(`frontend asset closure OK: ${visited.size} referenced files checked`);
