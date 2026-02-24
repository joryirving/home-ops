const express = require('express');
const session = require('express-session');
const http = require('http');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
const MemoryStore = require('memorystore')(session);
require('dotenv').config();

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
    const RedisStoreFactory = require('connect-redis').default || require('connect-redis');
    const { createClient } = require('redis');
    const redisClient = createClient({ url: process.env.REDIS_URL });
    redisClient.connect().catch((err) => console.error('Redis connect failed, falling back to MemoryStore:', err.message));
    console.log('Using Redis session store');
    return new RedisStoreFactory({ client: redisClient, prefix: 'miso-chat:' });
  } catch (err) {
    console.warn('REDIS_URL set but redis/connect-redis not installed; using MemoryStore fallback');
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
  const oidcIssuer = process.env.OIDC_ISSUER;
  passport.use('oidc', new (require('passport-openidconnect').Strategy)({
    issuer: oidcIssuer,
    authorizationURL: process.env.OIDC_AUTH_URL || (oidcIssuer + '/application/o/authorize/'),
    tokenURL: process.env.OIDC_TOKEN_URL || (oidcIssuer + '/application/o/token/'),
    userInfoURL: process.env.OIDC_USERINFO_URL || (oidcIssuer + '/application/o/userinfo/'),
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
      return res.status(401).send(`OIDC login failed: ${req.query.error}. Check client ID, secret, and callback URL.`);
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

app.get('/auth/oidc/callback', 
  passport.authenticate('oidc', { 
    successRedirect: '/',
    failureRedirect: '/login?error=oidc_failed'
  })
);

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

// Gateway WebSocket connection
let gatewayWs = null;
let reconnectAttempts = 0;

function nextReconnectDelayMs() {
  const base = 1000;
  const max = 30000;
  const exp = Math.min(max, base * Math.pow(2, reconnectAttempts));
  const jitter = Math.floor(Math.random() * 500);
  return exp + jitter;
}

function connectToGateway() {
  const gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  console.log(`Connecting to gateway: ${gatewayUrl}`);

  gatewayWs = new WebSocket(gatewayUrl);
  
  gatewayWs.on('open', () => {
    reconnectAttempts = 0;
    console.log('Connected to gateway!');
    startHeartbeat();
  });
  
  gatewayWs.on('message', (data) => {
    // Broadcast to all connected clients
    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data.toString());
      }
    });
  });
  
  gatewayWs.on('close', () => {
    if (heartbeat) clearInterval(heartbeat);
    reconnectAttempts += 1;
    const delay = nextReconnectDelayMs();
    console.log(`Gateway disconnected, reconnecting in ${delay}ms...`);
    setTimeout(connectToGateway, delay);
  });
  
  gatewayWs.on('error', (err) => {
    console.error('Gateway error:', err.message);
    if (heartbeat) clearInterval(heartbeat);
  });
}

// Heartbeat variable (declared outside function)
let heartbeat;

// Connect to gateway on start
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

  ws.on('message', (message) => {
    if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
      gatewayWs.send(message.toString());
    } else {
      ws.send(JSON.stringify({ error: 'Not connected to gateway' }));
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
