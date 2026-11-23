import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';

// Guards against runtime crashes such as <GitBranch /> without importing GitBranch.
// Runs without a browser or external dependencies, alongside the existing ERP tests.
const srcDir = new URL('../src/', import.meta.url);
const sourceFiles = readdirSync(srcDir).filter(name => name.endsWith('.jsx'));

function declaredJsxNames(source) {
  const declared = new Set();
  for (const match of source.matchAll(/import\s*\{([^}]+)\}\s*from\s*['"][^'"]+['"]/gs)) {
    for (const specifier of match[1].split(',')) {
      const localName = specifier.trim().split(/\s+as\s+/).at(-1)?.trim();
      if (localName) declared.add(localName);
    }
  }
  for (const match of source.matchAll(/import\s+([A-Za-z_$][\w$]*)\s+from\s*['"][^'"]+['"]/g)) {
    declared.add(match[1]);
  }
  for (const match of source.matchAll(/import\s+([A-Za-z_$][\w$]*)\s*,\s*\{/g)) {
    declared.add(match[1]);
  }
  for (const match of source.matchAll(/\b(?:function|class|const|let)\s+([A-Z][A-Za-z0-9_]*)\b/g)) {
    declared.add(match[1]);
  }
  // Components may also be passed as destructured function props.
  for (const match of source.matchAll(/function\s+\w+\s*\(\s*\{([^}]+)\}/g)) {
    for (const prop of match[1].split(',')) {
      const local = prop.trim().split(':').at(-1).split('=')[0].trim();
      if (/^[A-Z][A-Za-z0-9_]*$/.test(local)) declared.add(local);
    }
  }
  // <Icon /> is a dynamic prop or destructured item from a map of UI descriptors.
  declared.add('Icon');
  return declared;
}

test('every JSX component used in ERP screens is imported or declared', () => {
  for (const name of sourceFiles) {
    const source = readFileSync(new URL(name, srcDir), 'utf8');
    const declared = declaredJsxNames(source);
    const used = [...new Set([...source.matchAll(/<([A-Z][A-Za-z0-9_]*)\b/g)].map(match => match[1]))];
    const missing = used.filter(component => !declared.has(component));
    assert.deepEqual(missing, [], `${name} has undefined JSX components. Add the correct imports instead of hiding the form.`);
  }
});

test('shared transaction form uses a declared linked-document icon', () => {
  const main = readFileSync(new URL('main.jsx', srcDir), 'utf8');
  assert.match(main, /className="erp-form-source-header"><GitBranch\s+size=/);
  const lucideImports = main.match(/import\s*\{([\s\S]*?)\}\s*from\s*['"]lucide-react['"]/)?.[1] || '';
  assert.match(lucideImports, /\bGitBranch\b/, 'GitBranch must be imported for every Create/Edit transaction form');
});


test('JSX guard accepts component props but still catches undeclared components', () => {
  const source = 'function Field({Suggest, Renderer: Cell = Default}) { return <Suggest><Cell/><MissingIcon/></Suggest>; }';
  const names = declaredJsxNames(source);
  assert.ok(names.has('Suggest'));
  assert.ok(names.has('Cell'));
  assert.equal(names.has('MissingIcon'),false);
});
