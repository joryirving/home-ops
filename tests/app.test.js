const request = require('supertest');
const { app, validateConfig } = require('../server');

describe('Smoke auth behavior', () => {
  test('GET / redirects to login when unauthenticated', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(302);
    expect(res.headers.location).toBe('/login');
  });

  test('GET /api/auth sets no-store and unauthenticated by default', async () => {
    const res = await request(app).get('/api/auth');
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toContain('no-store');
    expect(res.body.authenticated).toBe(false);
  });
});

describe('Config validation', () => {
  const oldEnv = { ...process.env };
  afterEach(() => {
    process.env = { ...oldEnv };
  });

  test('throws if OIDC enabled but required env is missing', () => {
    process.env.OIDC_ENABLED = 'true';
    delete process.env.OIDC_ISSUER;
    delete process.env.OIDC_CLIENT_ID;
    delete process.env.OIDC_CLIENT_SECRET;
    expect(() => validateConfig()).toThrow(/missing required env vars/i);
  });
});
