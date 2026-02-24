const express = require('express');
const session = require('express-session');
const http = require('http');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const securityMiddleware = require('./security');

const app = express();
const server = http.createServer(app);
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
    secure: process.env.NODE_ENV === 'production',
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
app.get('/api/health', (req, res) => res.json({ status: 'healthy', uptime: process.uptime(), timestamp: new Date().toISOString() }));

// WebSocket with connection tracking
const clients = new Set();

server.on('upgrade', (request, socket, head) => wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request)));

let gatewayWs = null;
let gatewayConnected = false;

function connectToGateway() {
  const gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  console.log(`Connecting to gateway: ${gatewayUrl}`);
  
  gatewayWs = new WebSocket(gatewayUrl, { 
    handshakeTimeout: 5000,
    maxPayload: 1024 * 1024 // 1MB max message
  });
  
  gatewayWs.on('open', () => {
    console.log('Connected to gateway!');
    gatewayConnected = true;
    broadcastToClients({ type: 'gateway', connected: true });
  });
  
  gatewayWs.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      // Forward to all clients
      clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(data.toString());
        }
      });
    } catch {
      clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(data.toString());
        }
      });
    }
  });
  
  gatewayWs.on('close', () => {
    console.log('Gateway disconnected, reconnecting in 5s...');
    gatewayConnected = false;
    broadcastToClients({ type: 'gateway', connected: false });
    setTimeout(connectToGateway, 5000);
  });
  
  gatewayWs.on('error', (err) => {
    console.error('Gateway error:', err.message);
    gatewayConnected = false;
  });
  
  gatewayWs.on('pong', () => {
    // Heartbeat response
  });
}

function broadcastToClients(data) {
  const msg = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(msg);
    }
  });
}

function heartbeat() {
  if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
    gatewayWs.ping();
  }
}

// Gateway heartbeat
setInterval(heartbeat, 30000);

connectToGateway();

wss.on('connection', (ws, req) => {
  console.log('Client connected');
  clients.add(ws);
  
  // Send initial connection status
  ws.send(JSON.stringify({ 
    type: 'connection', 
    gateway: gatewayConnected,
    timestamp: new Date().toISOString()
  }));
  
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      
      // Handle typing indicator
      if (data.type === 'typing') {
        // Could forward to gateway if needed
        return;
      }
      
      // Forward to gateway
      if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
        gatewayWs.send(message.toString());
      } else {
        ws.send(JSON.stringify({ error: 'Not connected to gateway', type: 'error' }));
      }
    } catch {
      if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
        gatewayWs.send(message.toString());
      }
    }
  });
  
  ws.on('close', () => {
    console.log('Client disconnected');
    clients.delete(ws);
  });
  
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
});

// Client heartbeat - remove dead connections
const clientHeartbeat = setInterval(() => {
  wss.clients.forEach(ws => {
    if (ws.isAlive === false) {
      clients.delete(ws);
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(clientHeartbeat);
});

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
server.listen(PORT, () => console.log(`
🎉 OpenClaw Chat Server running on port ${PORT}
   Gateway: ${process.env.GATEWAY_URL || 'ws://localhost:18789'}
   Auth: ${process.env.OIDC_ENABLED === 'true' ? 'OIDC' : 'Local'}
   Login at: http://localhost:${PORT}/login
`));
