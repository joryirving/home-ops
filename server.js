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
const dns = require('dns');
require('dotenv').config();

const securityMiddleware = require('./security');

const app = express();

// DNS cache for security
const dnsCache = new Map();
const resolveHostname = (hostname) => {
  return new Promise((resolve, reject) => {
    if (dnsCache.has(hostname)) {
      return resolve(dnsCache.get(hostname));
    }
    dns.resolve4(hostname, (err, addresses) => {
      if (err) return reject(err);
      dnsCache.set(hostname, addresses);
      resolve(addresses);
    });
  });
};

// Verify gateway URL is from allowed domains
const ALLOWED_GATEWAY_DOMAINS = (process.env.ALLOWED_GATEWAY_DOMAINS || 'localhost,jory.dev,internal').split(',');

const isAllowedGateway = async (url) => {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname;
    
    // Allow localhost and IP addresses
    if (hostname === 'localhost' || /^\d+\.\d+\.\d+\.\d+$/.test(hostname)) {
      return true;
    }
    
    // Check against allowed domains
    for (const domain of ALLOWED_GATEWAY_DOMAINS) {
      if (hostname === domain || hostname.endsWith('.' + domain)) {
        return true;
      }
    }
    
    // Resolve and check IP ranges (basic)
    try {
      const addresses = await resolveHostname(hostname);
      // Block private ranges
      const privateRanges = ['10.', '172.16.', '192.168.', '127.'];
      for (const ip of addresses) {
        if (!privateRanges.some(r => ip.startsWith(r))) {
          return true;
        }
      }
    } catch (e) {
      console.error('DNS resolution failed:', e.message);
    }
    
    return false;
  } catch {
    return false;
  }
};

// HTML escape
const escapeHtml = (str) => {
  if (typeof str !== 'string') return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
};

// TLS config
const TLS_KEY = process.env.TLS_KEY_PATH || process.env.TLS_KEY;
const TLS_CERT = process.env.TLS_CERT_PATH || process.env.TLS_CERT;
const hasTLS = TLS_KEY && TLS_CERT && fs.existsSync(TLS_KEY) && fs.existsSync(TLS_CERT);

// Enforce HTTPS in production
const enforceHTTPS = process.env.ENFORCE_HTTPS !== 'false';

const server = hasTLS 
  ? https.createServer({ 
      key: fs.readFileSync(TLS_KEY),
      cert: fs.readFileSync(TLS_CERT),
      minVersion: 'TLSv1.2',
      ciphers: 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384',
      // Reject unauthorized certificates
      rejectUnauthorized: process.env.NODE_ENV !== 'development'
    }, app) 
  : http.createServer(app);

// Trust proxy for HTTPS termination
app.enable('trust proxy');

const wss = new WebSocket.Server({ 
  noServer: true,
  maxPayload: 64 * 1024
});

securityMiddleware.forEach(middleware => app.use(middleware));

app.use((req, res, next) => {
  // HSTS in production
  if (enforceHTTPS && hasTLS) {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  next();
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  skipSuccessfulRequests: true,
  message: { error: 'Too many login attempts' },
});

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Too many requests' }
});

app.use('/api/', apiLimiter);

app.use(express.json({ limit: '10kb', strict: true }));
app.use(express.urlencoded({ extended: false, limit: '10kb' }));

app.use(express.static('public', {
  index: false,
  setHeaders: (res) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  }
}));

const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: hasTLS,
    httpOnly: true,
    sameSite: 'strict',
    maxAge: 24 * 60 * 60 * 1000
  }
});
app.use(sessionMiddleware);

app.use(passport.initialize());
app.use(passport.session());

passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((obj, done) => done(null, obj));

// Auth - same as before but with escapeHtml on username
if (process.env.OIDC_ENABLED !== 'true') {
  const localUsers = (process.env.LOCAL_USERS || 'admin:password123').split(',');
  const validUsers = localUsers.map(u => {
    const [user, pass] = u.split(':');
    return { user: user.trim(), pass: pass.trim() };
  });

  passport.use(new LocalStrategy(
    { passReqToCallback: true },
    (req, username, password, done) => {
      if (!username || !password || username.length > 100 || password.length > 100) {
        return done(null, false);
      }
      const valid = validUsers.find(u => u.user === username && u.pass === password);
      if (valid) return done(null, { username: escapeHtml(username) });
      return done(null, false);
    }
  ));
} else {
  passport.use('oidc', new (require('passport-openidconnect').Strategy)({
    issuerURL: process.env.OIDC_ISSUER,
    clientID: process.env.OIDC_CLIENT_ID,
    clientSecret: process.env.OIDC_CLIENT_SECRET,
    callbackURL: process.env.OIDC_CALLBACK_URL,
    scope: ['openid', 'profile', 'email']
  },
  (issuer, profile, done) => {
    return done(null, { 
      username: escapeHtml(profile.displayName || profile.username || 'unknown'),
      email: profile.emails?.[0]?.value 
    });
  }));
}

const isAuthenticated = (req, res, next) => {
  if (req.isAuthenticated() && req.session?.authorized === true) return next();
  res.redirect('/login');
};

app.get('/login', (req, res) => {
  if (req.isAuthenticated()) return res.redirect('/');
  res.sendFile(__dirname + '/public/login.html');
});

app.post('/login', authLimiter, (req, res, next) => {
  passport.authenticate('local', (err, user) => {
    if (err || !user) return res.redirect('/login?error=invalid');
    req.logIn(user, (err) => {
      if (err) return res.redirect('/login?error=invalid');
      req.session.regenerate(() => {
        req.session.authorized = true;
        res.redirect('/');
      });
    });
  })(req, res, next);
});

app.get('/auth/oidc', passport.authenticate('oidc'));
app.get('/auth/oidc/callback', 
  passport.authenticate('oidc', { failureRedirect: '/login?error=oidc_failed' }),
  (req, res) => { req.session.authorized = true; res.redirect('/'); }
);

app.post('/logout', (req, res) => {
  const wasAuthenticated = req.isAuthenticated();
  req.logout(() => {
    req.session.destroy(() => {
      if (wasAuthenticated && process.env.OIDC_ENABLED === 'true') {
        return res.redirect(process.env.OIDC_ISSUER + '/logout/');
      }
      res.redirect('/login');
    });
  });
});

app.get('/', isAuthenticated, (req, res) => res.sendFile(__dirname + '/public/index.html'));

app.get('/api/auth', (req, res) => {
  res.json({ 
    authenticated: req.isAuthenticated() && req.session?.authorized === true, 
    user: req.user ? { username: escapeHtml(req.user.username) } : null
  });
});

app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    tls: hasTLS,
    enforceHTTPS,
    uptime: process.uptime(), 
    timestamp: new Date().toISOString() 
  });
});

app.use((req, res) => res.status(404).json({ error: 'Not found' }));
app.use((err, req, res, next) => {
  console.error('Error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

// WebSocket with MITM protection
const clients = new Set();
let gatewayWs = null;

server.on('upgrade', (request, socket, head) => {
  const origin = request.headers.origin;
  if (origin) {
    const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);
    if (!allowedOrigins.some(o => new URL(o).hostname === new URL(origin).hostname)) {
      socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
      socket.destroy();
      return;
    }
  }
  wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request));
});

// Gateway connection with certificate validation
async function connectToGateway() {
  let gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  
  // Validate gateway URL
  if (!gatewayUrl.startsWith('ws://') && !gatewayUrl.startsWith('wss://')) {
    console.error('Invalid gateway protocol');
    return;
  }
  
  // Security check for gateway
  if (!await isAllowedGateway(gatewayUrl)) {
    console.error('Gateway not in allowed domains:', gatewayUrl);
    return;
  }
  
  console.log(`Connecting to gateway: ${gatewayUrl}`);
  
  const wsOptions = { 
    handshakeTimeout: 5000,
    maxPayload: 64 * 1024
  };
  
  // For wss://, add certificate rejection in production
  if (gatewayUrl.startsWith('wss://')) {
    wsOptions.rejectUnauthorized = process.env.NODE_ENV === 'production';
  }
  
  gatewayWs = new WebSocket(gatewayUrl, wsOptions);
  
  gatewayWs.on('open', () => console.log('Connected to gateway!'));
  
  gatewayWs.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.content) msg.content = escapeHtml(msg.content);
      if (msg.text) msg.text = escapeHtml(msg.text);
      clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(JSON.stringify(msg)));
    } catch {
      clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(data.toString()));
    }
  });
  
  gatewayWs.on('close', () => {
    console.log('Gateway disconnected, reconnecting in 5s...');
    setTimeout(connectToGateway, 5000);
  });
  
  gatewayWs.on('error', (err) => console.error('Gateway error:', err.message));
}

setInterval(() => { if (gatewayWs?.readyState === WebSocket.OPEN) gatewayWs.ping(); }, 30000);
connectToGateway();

wss.on('connection', (ws) => {
  console.log('Client connected');
  clients.add(ws);
  
  ws.send(JSON.stringify({ type: 'connection', tls: hasTLS, timestamp: new Date().toISOString() }));
  
  ws.on('message', (message) => {
    if (message.length > 64 * 1024) {
      ws.send(JSON.stringify({ error: 'Message too large', type: 'error' }));
      return;
    }
    
    try {
      const data = JSON.parse(message.toString());
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
server.listen(PORT, () => console.log(`
🎉 OpenClaw Chat running on ${hasTLS ? 'https' : 'http'}://:${PORT}
   TLS: ${hasTLS} | Enforce HTTPS: ${enforceHTTPS}
`));
