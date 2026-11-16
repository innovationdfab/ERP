import test from 'node:test';
import assert from 'node:assert/strict';
import {canUseLocalAdminPreview} from '../src/admin-preview-policy.js';

test('local preview may run on localhost only in development', () => {
  assert.equal(canUseLocalAdminPreview(true, 'localhost'), true);
  assert.equal(canUseLocalAdminPreview(true, '127.0.0.1'), true);
  assert.equal(canUseLocalAdminPreview(true, '::1'), true);
});
test('production and remote hosts never receive unauthenticated admin UI', () => {
  for (const dev of [true,false]) {
    assert.equal(canUseLocalAdminPreview(dev, 'dfab-erp.vercel.app'), false);
    assert.equal(canUseLocalAdminPreview(dev, '192.168.1.15'), false);
  }
  assert.equal(canUseLocalAdminPreview(false, 'localhost'), false);
});
