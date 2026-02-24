const express = require('express');
const session = require('express-session');
const http = require('http');
const https = require('https');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const securityMiddleware = require('./security');

const app = express();

// Check for TLS config
const TLS_KEY = process.env.TLS_KEY_PATH || process.env.TLS_KEY;
const TLS_CERT = process.env.TLS_CERT_PATH || process.env.TLS_CERT;
const hasTLS = TLS_KEY && TLS_CERT && fs.existsSync(TLS_KEY) && fs.existsSync(TLS_CERT);

if (hasTLS) {
  const tlsOptions = {
    key: fs.readFileSync(TLS_KEY),
    cert: fs.readFileSync(TLS_CERT)
  };
  console.log('🔒 TLS enabled');
}

// Create server
const server = hasTLS 
  ? https.createServer(tlsOptions, app) 
  : http.createServer(app);

const wss = new WebSocket.Server({ noServer: true });

securityMiddleware.forEach(middleware => app.use(middleware));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: 'Too many login attempts, please try again later.' },
});

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Too many requests, please try again later.' }
});

app.use('/api/', apiLimiter);

app.use(express.json({ limit: '10kb' }));
app.use(express.static('public'));

const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: hasTLS, // Only secure in production with TLS
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

// Local Auth
if (process.env.OIDC_ENABLED !== 'true') {
  const localUsers = (process.env.LOCAL_USERS || 'admin:password123').split(',');
  const validUsers = localUsers.map(u => {
    const [user, pass] = u.split(':');
    return { user: user.trim(), pass: pass.trim() };
  });

  passport.use(new LocalStrategy(
    (username, password, done) => {
      const valid = validUsers.find(u => u.user === username && u.pass === password);
      if (valid) return done(null, { username });
      return done(null, false, { message: 'Invalid credentials' });
    }
  ));
} else {
  passport.use('oidc', new (require('passport-openidconnect').Strategy)({
    issuerURL: process.env.OIDC_ISSUER,
    authorizationURL: process.env.OIDC_ISSUER + '/authorization/',
    tokenURL: process.env.OIDC_ISSUER + '/token/',
    userInfoURL: process.env.OIDC_ISSUER + '/userinfo/',
    clientID: process.env.OIDC_CLIENT_ID,
    clientSecret: process.env.OIDC_CLIENT_SECRET,
    callbackURL: process.env.OIDC_CALLBACK_URL || '/auth/oidc/callback',
    scope: ['openid', 'profile', 'email']
  },
  (issuer, profile, done) => {
    return done(null, { username: profile.displayName || profile.username, email: profile.emails?.[0]?.value });
  }));
}

const isAuthenticated = (req, res, next) => req.isAuthenticated() ? next() : res.redirect('/login');

app.get('/login', (req, res) => res.sendFile(__dirname + '/public/login.html'));
app.post('/login', authLimiter, passport.authenticate('local', { successRedirect: '/', failureRedirect: '/login?error=invalid' }));
app.get('/auth/oidc', passport.authenticate('oidc'));
app.get('/auth/oidc/callback', passport.authenticate('oidc', { successRedirect: '/', failureRedirect: '/login?error=oidc_failed' }));

app.post('/logout', (req, res) => {
  req.logout(() => {
    if (process.env.OIDC_ENABLED === 'true' && process.env.OIDC_ISSUER) {
      return res.redirect(process.env.OIDC_ISSUER + '/logout/?next=' + encodeURIComponent(req.protocol + '://' + req.get('host') + '/login'));
    }
    res.redirect('/login');
  });
});

app.get('/', isAuthenticated, (req, res) => res.sendFile(__dirname + '/public/index.html'));
app.get('/api/auth', (req, res) => res.json({ authenticated: req.isAuthenticated(), user: req.user, oidc: process.env.OIDC_ENABLED === 'true' }));
app.get('/api/health', (req, res) => res.json({ status: 'healthy', tls: hasTLS, uptime: process.uptime(), timestamp: new Date().toISOString() }));

// Redirect HTTP to HTTPS in production
app.use((req, res, next) => {
  if (!hasTLS && process.env.NODE_ENV === 'production') {
    const httpsUrl = 'https://' + req.get('host') + req.url;
    return res.redirect(httpsUrl);
  }
  next();
});

// WebSocket
const clients = new Set();
let gatewayWs = null;
let gatewayConnected = false;

server.on('upgrade', (request, socket, head) => wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request)));

function connectToGateway() {
  const gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  console.log(`Connecting to gateway: ${gatewayUrl}`);
  
  gatewayWs = new WebSocket(gatewayUrl, { 
    handshakeTimeout: 5000,
    maxPayload: 1024 * 1024
  });
  
  gatewayWs.on('open', () => {
    console.log('Connected to gateway!');
    gatewayConnected = true;
    clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(JSON.stringify({ type: 'gateway', connected: true })));
  });
  
  gatewayWs.on('message', (data) => {
    const msg = data.toString();
    clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(msg));
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

wss.on('connection', (ws) => {
  console.log('Client connected');
  clients.add(ws);
  
  ws.send(JSON.stringify({ type: 'connection', gateway: gatewayConnected, tls: hasTLS, timestamp: new Date().toISOString() }));
  
  ws.on('message', (message) => {
    if (gatewayWs?.readyState === WebSocket.OPEN) {
      gatewayWs.send(message.toString());
    } else {
      ws.send(JSON.stringify({ error: 'Not connected to gateway', type: 'error' }));
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

wss.on('close', () => process.exit(1));

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
   Login at: ${PROTOCOL}://localhost:${PORT}/login
`));
