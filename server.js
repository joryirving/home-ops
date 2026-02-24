const express = require('express');
const session = require('express-session');
const http = require('http');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
const MemoryStore = require('memorystore')(session);

if (!process.env.NODE_ENV) process.env.NODE_ENV = 'production';
if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config({ quiet: true });
}

// Import security middleware
const securityMiddleware = require('./security');

function validateConfig() {
  if (process.env.OIDC_ENABLED === 'true') {
    const required = ['OIDC_ISSUER', 'OIDC_CLIENT_ID', 'OIDC_CLIENT_SECRET'];
    const missing = required.filter((k) => !process.env[k]);
    if (missing.length) {
      throw new Error(`OIDC_ENABLED=true but missing required env vars: ${missing.join(', ')}`);
    }
  }
  if (process.env.NODE_ENV === 'production' && (!process.env.SESSION_SECRET || process.env.SESSION_SECRET.includes('change-this'))) {
    throw new Error('SESSION_SECRET must be set to a strong value in production');
  }
}

function buildSessionStore() {
  if (!process.env.REDIS_URL) {
    return new MemoryStore({ checkPeriod: 24 * 60 * 60 * 1000 });
  }
  try {
    // Optional dependency path
    const { RedisStore } = require('connect-redis');
    const { createClient } = require('redis');
    const redisClient = createClient({ url: process.env.REDIS_URL });
    redisClient.connect().catch((err) => console.error('Redis connect failed, falling back to MemoryStore:', err.message));
    console.log('Using Redis session store');
    return new RedisStore({ client: redisClient, prefix: 'miso-chat:' });
  } catch (err) {
    console.warn(`REDIS_URL set but Redis store init failed (${err.message}); using MemoryStore fallback`);
    return new MemoryStore({ checkPeriod: 24 * 60 * 60 * 1000 });
  }
}

validateConfig();

const app = express();
app.set('trust proxy', 1);
const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

// Apply security middleware
securityMiddleware.forEach(middleware => app.use(middleware));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: { error: 'Too many requests, please try again later.' }
});
app.use('/api/', limiter);


// Middleware
app.use(express.json({ limit: '10kb' }));
app.use(express.static('public', { index: false }));

// Session config
const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  store: buildSessionStore(),
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    sameSite: process.env.SESSION_SAMESITE || 'lax',
    maxAge: 24 * 60 * 60 * 1000 // 24 hours
  }
});
app.use(sessionMiddleware);

// Passport initialization
app.use(passport.initialize());
app.use(passport.session());

// Serialize/deserialize user
passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((obj, done) => done(null, obj));

// Local Auth Strategy
if (process.env.OIDC_ENABLED !== 'true') {
  const localUsers = (process.env.LOCAL_USERS || 'admin:password123').split(',');
  const validUsers = localUsers.map(u => {
    const [user, pass] = u.split(':');
    return { user: user.trim(), pass: pass.trim() };
  });

  passport.use(new LocalStrategy(
    (username, password, done) => {
      const valid = validUsers.find(u => u.user === username && u.pass === password);
      if (valid) {
        return done(null, { username });
      }
      return done(null, false, { message: 'Invalid credentials' });
    }
  ));
} else {
  // OIDC Strategy
  const providerBase = process.env.OIDC_PROVIDER_URL
    ? process.env.OIDC_PROVIDER_URL.replace('/.well-known/openid-configuration', '')
    : null;
  const oidcIssuer = process.env.OIDC_EXPECTED_ISSUER || (providerBase ? `${providerBase}/` : process.env.OIDC_ISSUER);
  const publicIssuer = process.env.OIDC_ISSUER;
  passport.use('oidc', new (require('passport-openidconnect').Strategy)({
    issuer: oidcIssuer,
    authorizationURL: process.env.OIDC_AUTH_URL || (publicIssuer + '/application/o/authorize/'),
    tokenURL: process.env.OIDC_TOKEN_URL || (publicIssuer + '/application/o/token/'),
    userInfoURL: process.env.OIDC_USERINFO_URL || (publicIssuer + '/application/o/userinfo/'),
    clientID: process.env.OIDC_CLIENT_ID,
    clientSecret: process.env.OIDC_CLIENT_SECRET,
    callbackURL: process.env.OIDC_CALLBACK_URL || '/auth/oidc/callback',
    scope: ['profile', 'email']
  },
  (issuer, profile, done) => {
    return done(null, {
      username: profile.displayName || profile.username,
      email: profile.emails?.[0]?.value
    });
  }
  ));
}

// Auth middleware
const isAuthenticated = (req, res, next) => {
  if (req.isAuthenticated()) {
    return next();
  }
  res.redirect('/login');
};

// Login page
app.get('/login', (req, res) => {
  if (req.isAuthenticated && req.isAuthenticated()) {
    return res.redirect('/');
  }

  // When OIDC is enabled, send users to SSO unless we're returning with an error.
  if (process.env.OIDC_ENABLED === 'true') {
    if (req.query?.error) {
      const reason = req.query.reason ? ` (${req.query.reason})` : '';
      return res.status(401).send(`OIDC login failed: ${req.query.error}${reason}. Check client ID, secret, and callback URL.`);
    }
    return res.redirect('/auth/oidc');
  }

  res.sendFile(__dirname + '/public/login.html');
});

// Login handler (local auth)
app.post('/login', 
  passport.authenticate('local', { 
    successRedirect: '/',
    failureRedirect: '/login?error=invalid'
  })
);

// OIDC auth routes
app.get('/auth/oidc', passport.authenticate('oidc'));

app.get('/auth/oidc/callback', (req, res, next) => {
  passport.authenticate('oidc', (err, user, info) => {
    if (err) {
      const reason = encodeURIComponent(err.message || 'auth_error');
      console.error('OIDC callback error:', err.message || err);
      return res.redirect(`/login?error=oidc_failed&reason=${reason}`);
    }
    if (!user) {
      const reason = encodeURIComponent(info?.message || 'no_user');
      console.error('OIDC callback rejected user:', info || 'no info');
      return res.redirect(`/login?error=oidc_failed&reason=${reason}`);
    }
    req.logIn(user, (loginErr) => {
      if (loginErr) {
        const reason = encodeURIComponent(loginErr.message || 'login_error');
        console.error('OIDC login session error:', loginErr.message || loginErr);
        return res.redirect(`/login?error=oidc_failed&reason=${reason}`);
      }
      return res.redirect('/');
    });
  })(req, res, next);
});

// Logout
app.post('/logout', (req, res) => {
  req.logout(() => {
    if (process.env.OIDC_ENABLED === 'true' && process.env.OIDC_ISSUER) {
      const logoutUrl = process.env.OIDC_ISSUER + '/logout/';
      return res.redirect(logoutUrl + '?next=' + encodeURIComponent(req.protocol + '://' + req.get('host') + '/login'));
    }
    res.redirect('/login');
  });
});

// Chat page (protected)
app.get('/', isAuthenticated, (req, res) => {
  res.sendFile(__dirname + '/public/index.html');
});

// API: Check auth status
app.get('/api/auth', (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.json({ 
    authenticated: req.isAuthenticated(), 
    user: req.user,
    oidc: process.env.OIDC_ENABLED === 'true'
  });
});

// API: Health check
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// WebSocket upgrade handling (require authenticated session)
server.on('upgrade', (request, socket, head) => {
  sessionMiddleware(request, {}, () => {
    passport.initialize()(request, {}, () => {
      passport.session()(request, {}, () => {
        if (!request.isAuthenticated || !request.isAuthenticated()) {
          socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
          socket.destroy();
          return;
        }
        wss.handleUpgrade(request, socket, head, (ws) => {
          wss.emit('connection', ws, request);
        });
      });
    });
  });
});

// Gateway WebSocket connection (OpenClaw protocol v3)
const crypto = require('crypto');
let gatewayWs = null;
let gatewayReady = false;
let reconnectAttempts = 0;
let heartbeat;
let gatewayConnReqId = null;
const gatewayPendingSends = [];
const GATEWAY_SESSION_KEY = process.env.OPENCLAW_SESSION_KEY || 'main';

function nextReconnectDelayMs() {
  const base = 1000;
  const max = 30000;
  const exp = Math.min(max, base * Math.pow(2, reconnectAttempts));
  const jitter = Math.floor(Math.random() * 500);
  return exp + jitter;
}

function broadcastToClients(payload) {
  const wire = JSON.stringify(payload);
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(wire);
    }
  });
}

function sendGatewayReq(method, params = {}) {
  if (!gatewayWs || gatewayWs.readyState !== WebSocket.OPEN) return null;
  const id = crypto.randomUUID();
  gatewayWs.send(JSON.stringify({ type: 'req', id, method, params }));
  return id;
}

function flushQueuedMessages() {
  while (gatewayPendingSends.length > 0 && gatewayReady) {
    const msg = gatewayPendingSends.shift();
    sendGatewayReq('chat.send', {
      sessionKey: GATEWAY_SESSION_KEY,
      message: msg,
      idempotencyKey: crypto.randomUUID(),
    });
  }
}

function parseGatewayChatEvent(payload) {
  const msg = payload?.message;
  if (!msg) return null;
  if (typeof msg === 'string') return msg;
  if (typeof msg?.content === 'string') return msg.content;
  if (Array.isArray(msg?.content)) {
    return msg.content.map((c) => (typeof c === 'string' ? c : c?.text || '')).join('');
  }
  if (typeof msg?.text === 'string') return msg.text;
  return null;
}

function requestHistory() {
  sendGatewayReq('chat.history', { sessionKey: GATEWAY_SESSION_KEY, limit: 40 });
}

function handleGatewayFrame(raw) {
  let frame;
  try {
    frame = JSON.parse(raw.toString());
  } catch {
    return;
  }

  if (frame.type === 'event' && frame.event === 'connect.challenge') {
    const params = {
      minProtocol: 3,
      maxProtocol: 3,
      client: {
        id: 'gateway-client',
        version: '1.0.0',
        platform: 'node',
        mode: 'backend',
      },
      role: 'operator',
      scopes: ['operator.read', 'operator.write'],
      auth: {},
      locale: 'en-US',
      userAgent: 'miso-chat/1.0.0',
    };
    if (process.env.GATEWAY_AUTH_TOKEN) {
      params.auth.token = process.env.GATEWAY_AUTH_TOKEN;
    }
    gatewayConnReqId = crypto.randomUUID();
    gatewayWs.send(JSON.stringify({ type: 'req', id: gatewayConnReqId, method: 'connect', params }));
    return;
  }

  if (frame.type === 'res') {
    if (frame.id === gatewayConnReqId) {
      if (frame.ok) {
        gatewayReady = true;
        reconnectAttempts = 0;
        console.log('Gateway protocol connect complete');
        requestHistory();
        flushQueuedMessages();
        broadcastToClients({ type: 'status', connected: true });
      } else {
        gatewayReady = false;
        console.error('Gateway connect rejected:', frame.error?.message || frame.error || 'unknown');
        broadcastToClients({ type: 'error', content: `Gateway auth/connect failed: ${frame.error?.message || 'unknown'}` });
      }
      return;
    }

    if (!frame.ok) return;

    // chat.history response
    const payload = frame.payload;
    if (Array.isArray(payload)) {
      for (const item of payload) {
        const text = parseGatewayChatEvent({ message: item?.message || item });
        if (text) broadcastToClients({ content: text });
      }
    } else if (Array.isArray(payload?.messages)) {
      for (const item of payload.messages) {
        const text = parseGatewayChatEvent({ message: item?.message || item });
        if (text) broadcastToClients({ content: text });
      }
    }
    return;
  }

  if (frame.type === 'event' && frame.event === 'chat') {
    const text = parseGatewayChatEvent(frame.payload);
    if (text) {
      broadcastToClients({ content: text });
    }
    return;
  }
}

function connectToGateway() {
  const gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  console.log(`Connecting to gateway: ${gatewayUrl}`);

  gatewayReady = false;
  gatewayWs = new WebSocket(gatewayUrl);

  gatewayWs.on('open', () => {
    console.log('Gateway socket opened; waiting for connect.challenge...');
    startHeartbeat();
  });

  gatewayWs.on('message', handleGatewayFrame);

  gatewayWs.on('close', () => {
    gatewayReady = false;
    if (heartbeat) clearInterval(heartbeat);
    reconnectAttempts += 1;
    const delay = nextReconnectDelayMs();
    console.log(`Gateway disconnected, reconnecting in ${delay}ms...`);
    broadcastToClients({ type: 'status', connected: false });
    setTimeout(connectToGateway, delay);
  });

  gatewayWs.on('error', (err) => {
    gatewayReady = false;
    console.error('Gateway error:', err.message);
    if (heartbeat) clearInterval(heartbeat);
  });
}

function startHeartbeat() {
  if (heartbeat) clearInterval(heartbeat);
  let awaitingPong = false;
  gatewayWs.on('pong', () => { awaitingPong = false; });
  heartbeat = setInterval(() => {
    if (!gatewayWs || gatewayWs.readyState !== WebSocket.OPEN) return;
    if (awaitingPong) {
      console.warn('Gateway pong timeout, terminating socket');
      try { gatewayWs.terminate(); } catch (_) {}
      return;
    }
    awaitingPong = true;
    gatewayWs.ping();
  }, 25000);
}

// Handle client WebSocket connections
wss.on('connection', (ws) => {
  console.log('Client connected');

  if (gatewayReady) {
    ws.send(JSON.stringify({ type: 'status', connected: true }));
    requestHistory();
  } else {
    ws.send(JSON.stringify({ type: 'status', connected: false }));
  }

  ws.on('message', (message) => {
    let payload;
    try {
      payload = JSON.parse(message.toString());
    } catch {
      return;
    }

    if (payload?.type === 'message' && typeof payload?.content === 'string') {
      const msg = payload.content.trim();
      if (!msg) return;

      if (gatewayReady) {
        sendGatewayReq('chat.send', {
          sessionKey: GATEWAY_SESSION_KEY,
          message: msg,
          idempotencyKey: crypto.randomUUID(),
        });
      } else {
        gatewayPendingSends.push(msg);
        ws.send(JSON.stringify({ error: 'Gateway offline, message queued' }));
      }
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
  });

  ws.on('error', (err) => {
    console.error('Client websocket error:', err.message);
  });
});

function start() {
  connectToGateway();
  const PORT = process.env.PORT || 3000;
  return server.listen(PORT, () => {
    console.log(`
🎉 OpenClaw Chat Server running on port ${PORT}
   
   Gateway: ${process.env.GATEWAY_URL || 'ws://localhost:18789'}
   Auth: ${process.env.OIDC_ENABLED === 'true' ? 'OIDC' : 'Local'}
   Node Env: ${process.env.NODE_ENV || 'development'}
   
   Login at: http://localhost:${PORT}/login
  `);
  });
}

if (require.main === module) {
  start();
}

module.exports = { app, server, start, validateConfig, nextReconnectDelayMs };
