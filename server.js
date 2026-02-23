const express = require('express');
const session = require('express-session');
const http = require('http');
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

// Middleware
app.use(express.json());
app.use(express.static('public'));

// Session config
const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false } // Set true in production with HTTPS
});
app.use(sessionMiddleware);

// Auth middleware
const isAuthenticated = (req, res, next) => {
  if (req.session.user || process.env.OIDC_ENABLED !== 'true') {
    return next();
  }
  res.redirect('/login');
};

// Login page
app.get('/login', (req, res) => {
  res.sendFile(__dirname + '/public/login.html');
});

// Login handler (local auth)
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  
  // Parse local users from env
  const localUsers = (process.env.LOCAL_USERS || 'admin:password123').split(',');
  const validUsers = localUsers.map(u => {
    const [user, pass] = u.split(':');
    return { user: user.trim(), pass: pass.trim() };
  });
  
  const valid = validUsers.find(u => u.user === username && u.pass === password);
  
  if (valid) {
    req.session.user = { username };
    res.redirect('/');
  } else {
    res.redirect('/login?error=invalid');
  }
});

// Logout
app.post('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

// Chat page (protected)
app.get('/', isAuthenticated, (req, res) => {
  res.sendFile(__dirname + '/public/index.html');
});

// API: Check auth status
app.get('/api/auth', (req, res) => {
  res.json({ authenticated: !!req.session.user, user: req.session.user });
});

// WebSocket upgrade handling
server.on('upgrade', (request, socket, head) => {
  // Check session
  // Note: In production, properly validate session here
  
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
   
   Login at: http://localhost:${PORT}/login
  `);
});
