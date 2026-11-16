import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../src/main.jsx', import.meta.url), 'utf8');
const host = readFileSync(new URL('../src/in-app-dialog.jsx', import.meta.url), 'utf8');

test('all confirmation and alert interactions are routed through in-app UI', () => {
  assert.match(src, /showNotice as alert, askConfirmation as confirm, InAppDialogHost/);
  assert.match(src, /<InAppDialogHost\s*\/>/);
  assert.doesNotMatch(src, /\bwindow\.(alert|confirm|prompt)\s*\(/);
  assert.doesNotMatch(src, /\b(?<!await )confirm\(/); // confirmations must await the user
});
test('dialogs expose accessible confirmation and a dismiss option', () => {
  assert.match(host, /role="alertdialog"/);
  assert.match(host, /aria-modal="true"/);
  assert.match(host, /e\.key === 'Escape'/);
  assert.match(host, /Cancel/);
});
