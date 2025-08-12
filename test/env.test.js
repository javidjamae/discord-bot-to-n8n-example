import test from 'node:test';
import assert from 'node:assert/strict';
import { checkRequiredEnv } from '../env.js';

test('returns empty array when all env vars present', () => {
  const env = {
    DISCORD_TOKEN: 'token',
    APPLICATION_ID: 'app',
    N8N_WEBHOOK_URL: 'url'
  };
  assert.deepEqual(checkRequiredEnv(env), []);
});

test('returns names of missing env vars', () => {
  const env = { DISCORD_TOKEN: 'token' };
  assert.deepEqual(checkRequiredEnv(env), ['APPLICATION_ID', 'N8N_WEBHOOK_URL']);
});
