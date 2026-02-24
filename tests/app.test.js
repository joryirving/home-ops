const request = require('supertest');
const express = require('express');
const session = require('express-session');

// Mock app for testing
const createApp = () => {
  const app = express();
  app.use(express.json());
  app.use(express.static('public'));
  
  app.use(session({
    secret: 'test-secret',
    resave: false,
    saveUninitialized: false
  }));
  
  // Mock auth middleware
  const isAuthenticated = (req, res, next) => {
    if (req.session.user) return next();
    res.redirect('/login');
  };
  
  app.get('/login', (req, res) => res.sendFile(__dirname + '/../public/login.html'));
  app.post('/login', (req, res) => {
    const { username, password } = req.body;
    if (username === 'admin' && password === 'password123') {
      req.session.user = { username };
      return res.redirect('/');
    }
    res.redirect('/login?error=invalid');
  });
  app.post('/logout', (req, res) => {
    req.session.destroy();
    res.redirect('/login');
  });
  app.get('/', isAuthenticated, (req, res) => res.send('Chat'));
  app.get('/api/auth', (req, res) => {
    res.json({ authenticated: !!req.session.user, user: req.session.user });
  });
  app.get('/api/health', (req, res) => res.json({ status: 'healthy' }));
  
  return app;
};

describe('Authentication', () => {
  let app;
  
  beforeEach(() => {
    app = createApp();
  });
  
  test('GET /login returns login page', async () => {
    const res = await request(app).get('/login');
    expect(res.status).toBe(200);
  });
  
  test('GET / redirects to login when not authenticated', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(302);
    expect(res.headers.location).toBe('/login');
  });
  
  test('POST /login with valid credentials redirects to /', async () => {
    const res = await request(app)
      .post('/login')
      .send({ username: 'admin', password: 'password123' });
    expect(res.status).toBe(302);
    expect(res.headers.location).toBe('/');
  });
  
  test('POST /login with invalid credentials shows error', async () => {
    const res = await request(app)
      .post('/login')
      .send({ username: 'admin', password: 'wrong' });
    expect(res.status).toBe(302);
    expect(res.headers.location).toContain('error=invalid');
  });
  
  test('GET /api/auth returns unauthenticated initially', async () => {
    const res = await request(app).get('/api/auth');
    expect(res.status).toBe(200);
    expect(res.body.authenticated).toBe(false);
  });
  
  test('GET /api/auth returns authenticated after login', async () => {
    const agent = request.agent(app);
    await agent.post('/login').send({ username: 'admin', password: 'password123' });
    const res = await agent.get('/api/auth');
    expect(res.body.authenticated).toBe(true);
    expect(res.body.user.username).toBe('admin');
  });
});

describe('API Endpoints', () => {
  let app;
  
  beforeEach(() => {
    app = createApp();
  });
  
  test('GET /api/health returns healthy status', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('healthy');
  });
});

describe('Session Management', () => {
  test('session is destroyed on logout', async () => {
    const app = createApp();
    const agent = request.agent(app);
    
    // Login
    await agent.post('/login').send({ username: 'admin', password: 'password123' });
    
    // Verify authenticated
    let res = await agent.get('/api/auth');
    expect(res.body.authenticated).toBe(true);
    
    // Logout
    await agent.post('/logout');
    
    // Verify not authenticated
    res = await agent.get('/api/auth');
    expect(res.body.authenticated).toBe(false);
  });
});
