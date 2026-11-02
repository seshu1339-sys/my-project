// The server modules must stay independent, like the app modules (test/module_independence_test.dart): each in its own folder, requiring
// nothing from another module. Removing or changing one must not break the others. ai-core is the one shared library, not a feature.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readdirSync, readFileSync} = require('node:fs');
const {join, relative, resolve, dirname, sep} = require('node:path');

const SHARED = 'ai-core';
const modules = readdirSync(__dirname, {withFileTypes: true}).filter(e => e.isDirectory()).map(e => e.name);
const jsFiles = dir => readdirSync(dir, {withFileTypes: true}).flatMap(e => {
  if (e.isDirectory()) return e.name === 'node_modules' ? [] : jsFiles(join(dir, e.name));
  return e.name.endsWith('.js') ? [join(dir, e.name)] : [];
});
const requires = file => [...readFileSync(file, 'utf8').matchAll(/require\('(\.[^']+)'\)/g)].map(m => resolve(dirname(file), m[1]));

test('there is a folder per module', () => {
  assert.ok(modules.includes('plans'));
});

for (const id of modules) {
  test(`server module "${id}" requires nothing from another module`, () => {
    for (const file of jsFiles(join(__dirname, id))) {
      for (const target of requires(file)) {
        const inside = relative(__dirname, target);
        if (inside.startsWith('..')) continue;
        const other = inside.split(sep)[0];
        assert.ok(other === id || other === SHARED, `${relative(__dirname, file)} requires module ${other}`);
      }
    }
  });
}

test('only functions/index.js loads a server module', () => {
  const root = dirname(__dirname);
  const outside = readdirSync(root, {withFileTypes: true}).filter(e => e.isFile() && e.name.endsWith('.js') && e.name !== 'index.js').map(e => join(root, e.name));
  for (const file of outside) {
    for (const target of requires(file)) {
      assert.ok(relative(__dirname, target).startsWith('..'), `${file} loads a module directly`);
    }
  }
});

test('the module gate file reads plan documents, not the plans module', () => {
  const gate = readFileSync(join(dirname(__dirname), 'plan-gate.js'), 'utf8');
  assert.equal(/require\(/.test(gate), false);
});
