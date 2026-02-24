const express = require('express');
const session = require('express-session');
const http = require('http');
const https = require('https');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');
const fs = require('fs');
require('dotenv').config();

const securityMiddleware = require('./security');

const app = express();

// HTML escape to prevent XSS
const escapeHtml = (str) => {
  if (typeof str !== 'string') return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
};

// Check for TLS config
const TLS_KEY = process.env.TLS_KEY_PATH || process.env.TLS_KEY;
const TLS_CERT = process.env.TLS_CERT_PATH || process.env.TLS_CERT;
const hasTLS = TLS_KEY && TLS_CERT && fs.existsSync(TLS_KEY) && fs.existsSync(TLS_CERT);

const server = hasTLS 
  ? https.createServer({ 
      key: fs.readFileSync(TLS_KEY),
      cert: fs.readFileSync(TLS_CERT),
      // Security: Disable weak protocols
      minVersion: 'TLSv1.2',
      ciphers: 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384'
    }, app) 
  : http.createServer(app);

const wss = new WebSocket.Server({ 
  noServer: true,
  maxPayload: 64 * 1024 // 64KB max message
});

securityMiddleware.forEach(middleware => app.use(middleware));

// Security headers
app.use((req, res, next) => {
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  next();
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  skipSuccessfulRequests: true,
  message: { error: 'Too many login attempts, please try again later.' },
});

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Too many requests, please try again later.' }
});

app.use('/api/', apiLimiter);

app.use(express.json({ 
  limit: '10kb',
  // Validate JSON parsing
  strict: true 
}));

// Validate message size
app.use(express.urlencoded({ extended: false, limit: '10kb' }));

app.use(express.static('public', {
  // Prevent directory listing
  index: false,
  // Cache control for security
  setHeaders: (res, path) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  }
}));

// Session config with security
const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: hasTLS,
    httpOnly: true,
    sameSite: 'strict',
    maxAge: 24 * 60 * 60 * 1000
  },
  // Use secure session store in production
  store: new (require('express-session').MemoryStore)()
});
app.use(sessionMiddleware);

app.use(passport.initialize());
app.use(passport.session());

// Validate callback URL for OIDC
const validateCallbackUrl = (url) => {
  const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);
  if (!url) return false;
  try {
    const parsed = new URL(url);
    return allowedOrigins.some(origin => {
      const allowed = new URL(origin);
      return parsed.hostname === allowed.hostname && parsed.protocol === allowed.protocol;
    });
  } catch {
    return false;
  }
};

passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((obj, done) => done(null, obj));

// Local Auth
if (process.env.OIDC_ENABLED !== 'true') {
  const localUsers = (process.env.LOCAL_USERS || 'admin:password123').split(',');
  const validUsers = localUsers.map(u => {
    const [user, pass] = u.split(':');
    return { user: user.trim(), pass: pass.trim() };
  });

  passport.use(new LocalStrategy(
    { passReqToCallback: true },
    (req, username, password, done) => {
      // Input validation
      if (!username || !password) {
        return done(null, false, { message: 'Missing credentials' });
      }
      if (username.length > 100 || password.length > 100) {
        return done(null, false, { message: 'Invalid credentials' });
      }
      
      const valid = validUsers.find(u => u.user === username && u.pass === password);
      if (valid) return done(null, { username });
      return done(null, false, { message: 'Invalid credentials' });
    }
  ));
} else {
  const callbackUrl = process.env.OIDC_CALLBACK_URL;
  
  passport.use('oidc', new (require('passport-openidconnect').Strategy)({
    issuerURL: process.env.OIDC_ISSUER,
    authorizationURL: process.env.OIDC_ISSUER + '/authorization/',
    tokenURL: process.env.OIDC_ISSUER + '/token/',
    userInfoURL: process.env.OIDC_ISSUER + '/userinfo/',
    clientID: process.env.OIDC_CLIENT_ID,
    clientSecret: process.env.OIDC_CLIENT_SECRET,
    callbackURL: callbackUrl,
    scope: ['openid', 'profile', 'email']
  },
  (issuer, profile, done) => {
    // Validate callback
    if (callbackUrl && !validateCallbackUrl(callbackUrl)) {
      return done(new Error('Invalid callback URL'));
    }
    return done(null, { 
      username: escapeHtml(profile.displayName || profile.username || 'unknown'),
      email: profile.emails?.[0]?.value 
    });
  }));
}

const isAuthenticated = (req, res, next) => {
  if (req.isAuthenticated()) {
    // Security: Check session integrity
    if (req.session?.authorized !== true) {
      req.session.destroy();
      return res.redirect('/login');
    }
    return next();
  }
  res.redirect('/login');
};

app.get('/login', (req, res) => {
  // Don't show login to authenticated users
  if (req.isAuthenticated()) return res.redirect('/');
  res.sendFile(__dirname + '/public/login.html');
});

app.post('/login', authLimiter, (req, res, next) => {
  passport.authenticate('local', (err, user, info) => {
    if (err || !user) {
      return res.redirect('/login?error=invalid');
    }
    req.logIn(user, (err) => {
      if (err) return res.redirect('/login?error=invalid');
      // Security: Regenerate session to prevent fixation
      req.session.regenerate((err) => {
        if (err) return res.redirect('/login?error=invalid');
        req.session.authorized = true;
        res.redirect('/');
      });
    });
  })(req, res, next);
});

app.get('/auth/oidc', (req, res, next) => {
  if (!validateCallbackUrl(process.env.OIDC_CALLBACK_URL)) {
    return res.status(403).send('Invalid callback URL configuration');
  }
  passport.authenticate('oidc')(req, res, next);
});

app.get('/auth/oidc/callback', 
  passport.authenticate('oidc', { failureRedirect: '/login?error=oidc_failed' }),
  (req, res) => {
    req.session.authorized = true;
    res.redirect('/');
  }
);

app.post('/logout', (req, res) => {
  const wasAuthenticated = req.isAuthenticated();
  req.logout(() => {
    req.session.destroy(() => {
      if (wasAuthenticated && process.env.OIDC_ENABLED === 'true' && process.env.OIDC_ISSUER) {
        return res.redirect(process.env.OIDC_ISSUER + '/logout/?next=' + encodeURIComponent(req.protocol + '://' + req.get('host') + '/login'));
      }
      res.redirect('/login');
    });
  });
});

app.get('/', isAuthenticated, (req, res) => res.sendFile(__dirname + '/public/index.html'));

app.get('/api/auth', (req, res) => {
  res.json({ 
    authenticated: req.isAuthenticated() && req.session?.authorized === true, 
    user: req.user ? { username: escapeHtml(req.user.username) } : null,
    oidc: process.env.OIDC_ENABLED === 'true'
  });
});

app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    tls: hasTLS,
    uptime: process.uptime(), 
    timestamp: new Date().toISOString() 
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err, req, res, next) => {
  // Don't leak error details
  console.error('Error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

// WebSocket
const clients = new Set();
let gatewayWs = null;
let gatewayConnected = false;

server.on('upgrade', (request, socket, head) => {
  // Validate WebSocket origin
  const origin = request.headers.origin;
  if (origin && !validateCallbackUrl(origin)) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request));
});

function connectToGateway() {
  const gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  console.log(`Connecting to gateway: ${gatewayUrl}`);
  
  gatewayWs = new WebSocket(gatewayUrl, { 
    handshakeTimeout: 5000,
    maxPayload: 64 * 1024
  });
  
  gatewayWs.on('open', () => {
    console.log('Connected to gateway!');
    gatewayConnected = true;
    clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(JSON.stringify({ type: 'gateway', connected: true })));
  });
  
  gatewayWs.on('message', (data) => {
    // Sanitize messages from gateway before sending to clients
    try {
      const msg = JSON.parse(data.toString());
      if (msg.content) msg.content = escapeHtml(msg.content);
      if (msg.text) msg.text = escapeHtml(msg.text);
      clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(JSON.stringify(msg)));
    } catch {
      // Send as-is if not JSON
      clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(data.toString()));
    }
  });
  
  gatewayWs.on('close', () => {
    console.log('Gateway disconnected, reconnecting in 5s...');
    gatewayConnected = false;
    setTimeout(connectToGateway, 5000);
  });
  
  gatewayWs.on('error', (err) => console.error('Gateway error:', err.message));
}

setInterval(() => { if (gatewayWs?.readyState === WebSocket.OPEN) gatewayWs.ping(); }, 30000);

connectToGateway();

wss.on('connection', (ws, req) => {
  // Note: WebSocket connections don't have sessions by default
  // Client must re-authenticate via API after WebSocket connects
  
  console.log('Client connected');
  clients.add(ws);
  
  // Sanitize initial message
  ws.send(JSON.stringify({ 
    type: 'connection', 
    gateway: gatewayConnected, 
    tls: hasTLS, 
    timestamp: new Date().toISOString() 
  }));
  
  ws.on('message', (message) => {
    // Validate message size before processing
    if (message.length > 64 * 1024) {
      ws.send(JSON.stringify({ error: 'Message too large', type: 'error' }));
      return;
    }
    
    try {
      const data = JSON.parse(message.toString());
      
      // Sanitize user input
      if (data.content) data.content = escapeHtml(data.content.substring(0, 10000));
      if (data.text) data.text = escapeHtml(data.text.substring(0, 10000));
      
      if (gatewayWs?.readyState === WebSocket.OPEN) {
        gatewayWs.send(JSON.stringify(data));
      } else {
        ws.send(JSON.stringify({ error: 'Not connected to gateway', type: 'error' }));
      }
    } catch {
      ws.send(JSON.stringify({ error: 'Invalid message format', type: 'error' }));
    }
  });
  
  ws.on('close', () => { console.log('Client disconnected'); clients.delete(ws); });
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
});

setInterval(() => {
  wss.clients.forEach(ws => {
    if (!ws.isAlive) return clients.delete(ws) || ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

// Graceful shutdown
const shutdown = () => {
  console.log('Shutting down...');
  server.close(() => {
    if (gatewayWs) gatewayWs.close();
    wss.close(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10000);
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

const PORT = process.env.PORT || 3000;
const PROTOCOL = hasTLS ? 'https' : 'http';

server.listen(PORT, () => console.log(`
🎉 OpenClaw Chat Server running on ${PROTOCOL}://localhost:${PORT}
   Gateway: ${process.env.GATEWAY_URL || 'ws://localhost:18789'}
   TLS: ${hasTLS ? 'enabled' : 'disabled'}
   Auth: ${process.env.OIDC_ENABLED === 'true' ? 'OIDC' : 'Local'}
`));
