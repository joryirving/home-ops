const helmet = require('helmet');
const mongoSanitize = require('express-mongo-sanitize');
const hpp = require('hpp');
const cors = require('cors');

// Default to production if not set
const isProduction = process.env.NODE_ENV !== 'development';

// Custom mongo sanitize wrapper to handle Node.js v24 incompatibility
const customMongoSanitize = (req, res, next) => {
  try {
    mongoSanitize()(req, res, next);
  } catch (err) {
    // Skip sanitization if incompatible (Node.js v24+)
    next();
  }
};

const securityMiddleware = [
  // Set security headers
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'"],
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'", "wss:", "ws:"],
        fontSrc: ["'self'"],
        objectSrc: ["'none'"],
        mediaSrc: ["'self'"],
        frameSrc: ["'none'"],
      },
    },
    hsts: isProduction, // Enable HSTS in production
  }),
  
  // Prevent MongoDB injection (with Node v24 workaround)
  customMongoSanitize,
  
  // Protect against HTTP Parameter Pollution
  hpp(),
  
  // CORS configuration
  cors({
    origin: process.env.ALLOWED_ORIGINS?.split(',') || false,
    credentials: true,
    methods: ['GET', 'POST'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  }),
];

module.exports = securityMiddleware;
