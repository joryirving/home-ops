const express = require('express');
const session = require('express-session');
const http = require('http');
const WebSocket = require('ws');
const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const rateLimit = require('express-rate-limit');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Import security middleware
const securityMiddleware = require('./security');

console.log("=== DEBUG ENV ===");
console.log("OIDC_ENABLED:", process.env.OIDC_ENABLED);
console.log("OIDC_ISSUER:", process.env.OIDC_ISSUER);
console.log("OPENCLAW_URL:", process.env.OPENCLAW_URL);
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
app.use(express.urlencoded({ extended: false }));
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

// ============ SESSIONS API ============

// Helper to call OpenClaw CLI
function callOpenClaw(args) {
  return new Promise((resolve, reject) => {
    const openclaw = spawn('openclaw', args, {
      cwd: process.env.OPENCLAW_CWD || '/home/node/.openclaw/workspace',
      env: { ...process.env }
    });
    
    let stdout = '';
    let stderr = '';
    
    openclaw.stdout.on('data', (data) => {
      stdout += data.toString();
    });
    
    openclaw.stderr.on('data', (data) => {
      stderr += data.toString();
    });
    
    openclaw.on('close', (code) => {
      if (code === 0) {
        resolve(stdout);
      } else {
        reject(new Error(stderr || `Exit code ${code}`));
      }
    });
    
    openclaw.on('error', (err) => {
      reject(err);
    });
  });
}

// GET /api/sessions - List all sessions
app.get('/api/sessions', isAuthenticated, async (req, res) => {
  try {
    const sessionsDir = process.env.OPENCLAW_SESSIONS_DIR || '/home/node/.openclaw/agents/main/sessions';
    
    if (!fs.existsSync(sessionsDir)) {
      return res.json({ sessions: [] });
    }
    
    const files = fs.readdirSync(sessionsDir)
      .filter(f => f.endsWith('.jsonl') && !f.includes('.deleted.'))
      .map(f => {
        const filePath = path.join(sessionsDir, f);
        const stats = fs.statSync(filePath);
        // Extract session key from filename
        const sessionKey = f.replace('.jsonl', '');
        return {
          sessionKey,
          lastModified: stats.mtime.toISOString(),
          size: stats.size
        };
      })
      .sort((a, b) => new Date(b.lastModified) - new Date(a.lastModified));
    
    res.json({ sessions: files });
  } catch (error) {
    console.error('Error listing sessions:', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /api/sessions/:sessionKey/history - Get session history
app.get('/api/sessions/:sessionKey/history', isAuthenticated, async (req, res) => {
  try {
    const { sessionKey } = req.params;
    const sessionsDir = process.env.OPENCLAW_SESSIONS_DIR || '/home/node/.openclaw/agents/main/sessions';
    const filePath = path.join(sessionsDir, `${sessionKey}.jsonl`);
    
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Session not found' });
    }
    
    const content = fs.readFileSync(filePath, 'utf-8');
    const lines = content.trim().split('\n').filter(l => l);
    
    // Parse JSONL and extract messages
    const messages = [];
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (entry.type === 'message' || entry.type === 'reply') {
          messages.push({
            id: entry.id,
            type: entry.type,
            content: entry.content || entry.text || entry.message,
            timestamp: entry.timestamp,
            role: entry.role || (entry.type === 'reply' ? 'assistant' : 'user')
          });
        }
      } catch (e) {
        // Skip malformed lines
      }
    }
    
    res.json({ sessionKey, messages });
  } catch (error) {
    console.error('Error getting session history:', error);
    res.status(500).json({ error: error.message });
  }
});

// POST /api/sessions/:sessionKey/send - Send message to a session
app.post('/api/sessions/:sessionKey/send', isAuthenticated, async (req, res) => {
  try {
    const { sessionKey } = req.params;
    const { message } = req.body;
    
    if (!message) {
      return res.status(400).json({ error: 'Message is required' });
    }
    
    console.log(`Sending message to session ${sessionKey}:`, message);
    
    // Use OpenClaw CLI to send message and get response
    const args = [
      'agent',
      '--session-id', sessionKey,
      '--message', message,
      '--json'
    ];
    
    // Check if we should deliver the response
    if (process.env.AUTO_DELIVER === 'true') {
      args.push('--deliver');
    }
    
    const result = await callOpenClaw(args);
    
    try {
      const json = JSON.parse(result);
      res.json({ success: true, response: json });
    } catch {
      res.json({ success: true, response: result });
    }
  } catch (error) {
    console.error('Error sending message:', error);
    res.status(500).json({ error: error.message });
  }
});

// POST /api/sessions/:sessionKey/message - Send message via WebSocket (for real-time)
app.post('/api/sessions/:sessionKey/message', isAuthenticated, async (req, res) => {
  try {
    const { sessionKey } = req.params;
    const { message } = req.body;
    
    if (!message) {
      return res.status(400).json({ error: 'Message is required' });
    }
    
    // Broadcast to WebSocket clients for this session
    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN && client.sessionKey === sessionKey) {
        client.send(JSON.stringify({
          type: 'message',
          content: message,
          role: 'user',
          timestamp: new Date().toISOString()
        }));
      }
    });
    
    res.json({ success: true });
  } catch (error) {
    console.error('Error broadcasting message:', error);
    res.status(500).json({ error: error.message });
  }
});

// WebSocket upgrade handling
server.on('upgrade', (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  const sessionKey = url.pathname.split('/').pop();
  
  // Check if this is a session WebSocket
  if (url.pathname.startsWith('/api/sessions/') && url.pathname.endsWith('/ws')) {
    wss.handleUpgrade(request, socket, head, (ws) => {
      ws.sessionKey = sessionKey;
      wss.emit('sessionConnection', ws, request, sessionKey);
    });
  } else {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  }
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
    const msg = data.toString();
    
    // Parse and route to correct session clients
    try {
      const parsed = JSON.parse(msg);
      
      wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          // Send to all session-specific clients
          client.send(msg);
        }
      });
    } catch {
      // Not JSON, broadcast to all
      wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(msg);
        }
      });
    }
  });
  
  gatewayWs.on('close', () => {
    console.log('Gateway disconnected, reconnecting in 5s...');
    setTimeout(connectToGateway, 5000);
  });
  
  gatewayWs.on('error', (err) => {
    console.error('Gateway error:', err.message);
  });
}

// Connect to gateway on start
connectToGateway();

// Handle client WebSocket connections (generic)
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

// Handle session-specific WebSocket connections
wss.on('sessionConnection', (ws, req, sessionKey) => {
  console.log(`Session client connected: ${sessionKey}`);
  
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      
      // Forward to gateway with session context
      if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
        gatewayWs.send(JSON.stringify({
          ...data,
          sessionKey
        }));
      }
      
      // Also broadcast locally
      wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN && client.sessionKey === sessionKey) {
          client.send(message.toString());
        }
      });
    } catch (e) {
      ws.send(JSON.stringify({ error: 'Invalid message format' }));
    }
  });
  
  ws.on('close', () => {
    console.log(`Session client disconnected: ${sessionKey}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`
🎉 Miso-Chat Server running on port ${PORT}
   
   Gateway: ${process.env.GATEWAY_URL || 'ws://localhost:18789'}
   Sessions Dir: ${process.env.OPENCLAW_SESSIONS_DIR || '/home/node/.openclaw/agents/main/sessions'}
   Auth: ${process.env.OIDC_ENABLED === 'true' ? 'OIDC' : 'Local'}
   Node Env: ${process.env.NODE_ENV || 'development'}
   
   Login at: http://localhost:${PORT}/login
   
   API Endpoints:
   - GET  /api/sessions              - List all sessions
   - GET  /api/sessions/:key/history - Get session history
   - POST /api/sessions/:key/send    - Send message to session
   - WS   /api/sessions/:key/ws      - Real-time session WebSocket
  `);
});
