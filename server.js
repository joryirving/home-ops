const express = require('express');
const session = require('express-session');
const http = require('http');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
require('dotenv').config();

// Import security middleware
const securityMiddleware = require('./security');

console.log("=== DEBUG ENV ===");
console.log("OIDC_ENABLED:", process.env.OIDC_ENABLED);
console.log("OIDC_ISSUER:", process.env.OIDC_ISSUER);
console.log("OIDC_CLIENT_ID:", process.env.OIDC_CLIENT_ID);
console.log("=== END DEBUG ===");
const app = express();
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

// WebSocket rate limiting (simple)
let wsConnections = new Map();
const wsRateLimit = (ws) => {
  const ip = ws.upgradeReq?.connection?.remoteAddress;
  const now = Date.now();
  const last = wsConnections.get(ip) || 0;
  if (now - last < 100) { // Max 10 msg/sec
    ws.close();
    return false;
  }
  wsConnections.set(ip, now);
  return true;
};

// Middleware
app.use(express.json({ limit: '10kb' }));
app.use(express.static('public'));

// Session config
const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    sameSite: 'strict',
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
  passport.use('oidc', new (require('passport-openidconnect').Strategy)({
    issuer: process.env.OIDC_ISSUER,
    authorizationURL: process.env.OIDC_ISSUER + '/authorization/',
    tokenURL: process.env.OIDC_ISSUER + '/token/',
    userInfoURL: process.env.OIDC_ISSUER + '/userinfo/',
    clientID: process.env.OIDC_CLIENT_ID,
    clientSecret: process.env.OIDC_CLIENT_SECRET,
    callbackURL: process.env.OIDC_CALLBACK_URL || '/auth/oidc/callback',
    scope: ['openid', 'profile', 'email']
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

// WebSocket upgrade handling
server.on('upgrade', (request, socket, head) => {
  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit('connection', ws, request);
  });
});

// Gateway WebSocket connection
let gatewayWs = null;

function connectToGateway() {
  const gatewayUrl = process.env.GATEWAY_URL || 'ws://localhost:18789';
  console.log(`Connecting to gateway: ${gatewayUrl}`);
  
  gatewayWs = new WebSocket(gatewayUrl);
  
  gatewayWs.on('open', () => {
    console.log('Connected to gateway!');
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
    console.log('Gateway disconnected, reconnecting in 5s...');
    clearInterval(heartbeat);
    setTimeout(connectToGateway, 5000);
  });

  // Heartbeat to keep connection alive
  const heartbeat = setInterval(() => {
    if (gatewayWs.readyState === WebSocket.OPEN) {
      gatewayWs.ping();
    }
  }, 30000);
    console.log('Gateway disconnected, reconnecting in 5s...');
    setTimeout(connectToGateway, 5000);
  });
  
  gatewayWs.on('error', (err) => {
    console.error('Gateway error:', err.message);
  });
}

// Connect to gateway on start
connectToGateway();

// Handle client WebSocket connections
wss.on('connection', (ws, req) => {
  console.log('Client connected');
  
  ws.on('message', (message) => {
    // Forward to gateway
    if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
      gatewayWs.send(message.toString());
    } else {
      ws.send(JSON.stringify({ error: 'Not connected to gateway' }));
    }
  });
  
  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`
🎉 OpenClaw Chat Server running on port ${PORT}
   
   Gateway: ${process.env.GATEWAY_URL || 'ws://localhost:18789'}
   Auth: ${process.env.OIDC_ENABLED === 'true' ? 'OIDC' : 'Local'}
   Node Env: ${process.env.NODE_ENV || 'development'}
   
   Login at: http://localhost:${PORT}/login
  `);
});
