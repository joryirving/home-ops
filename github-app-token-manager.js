// GitHub App Token Manager for OpenClaw
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

class GitHubAppTokenManager {
  constructor() {
    this.appId = process.env.GITHUB_APP_ID;
    this.installationId = process.env.GITHUB_APP_INSTALLATION_ID;
    this.privateKey = process.env.GITHUB_APP_PRIVATE_KEY?.replace(/\\n/g, '\n');
    
    this.currentToken = null;
    this.tokenExpiration = null;
    this.refreshTimer = null;
    
    if (!this.appId || !this.installationId || !this.privateKey) {
      throw new Error('Missing required GitHub App environment variables');
    }
    
    // Initialize token and schedule refresh
    this.initialize();
  }
  
  initialize() {
    this.generateToken();
    this.scheduleRefresh();
  }
  
  generateJWT() {
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      iat: now,
      exp: now + (10 * 60), // 10 minutes
      iss: this.appId
    };
    
    return jwt.sign(payload, this.privateKey, { algorithm: 'RS256' });
  }
  
  async generateToken() {
    try {
      const jwtToken = this.generateJWT();
      
      const response = await fetch(`https://api.github.com/app/installations/${this.installationId}/access_tokens`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${jwtToken}`,
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'OpenClaw-GitHub-App'
        }
      });
      
      if (!response.ok) {
        throw new Error(`Failed to get installation token: ${response.status}`);
      }
      
      const data = await response.json();
      this.currentToken = data.token;
      // Set expiration 5 minutes before actual expiration for safety buffer
      this.tokenExpiration = new Date(data.expires_at).getTime() - (5 * 60 * 1000);
      
      console.log('GitHub App token refreshed successfully');
    } catch (error) {
      console.error('Error generating GitHub App token:', error.message);
      throw error;
    }
  }
  
  scheduleRefresh() {
    // Clear existing timer if any
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
    }
    
    // Calculate time until refresh (5 minutes before expiration)
    const now = Date.now();
    let timeUntilRefresh = (this.tokenExpiration - now);
    
    // Ensure we don't have negative time
    if (timeUntilRefresh <= 0) {
      timeUntilRefresh = 60000; // Refresh in 1 minute if already expired
    } else if (timeUntilRefresh > 55 * 60 * 1000) { // More than 55 mins
      timeUntilRefresh = 55 * 60 * 1000; // Max refresh in 55 mins
    }
    
    console.log(`Scheduling next token refresh in ${Math.round(timeUntilRefresh / 1000)} seconds`);
    
    this.refreshTimer = setTimeout(async () => {
      try {
        await this.generateToken();
        this.scheduleRefresh(); // Schedule next refresh
      } catch (error) {
        console.error('Failed to refresh token, retrying in 1 minute:', error.message);
        // Retry in 1 minute if failed
        setTimeout(() => {
          this.scheduleRefresh();
        }, 60000);
      }
    }, timeUntilRefresh);
  }
  
  getToken() {
    if (!this.currentToken) {
      throw new Error('No valid GitHub App token available');
    }
    
    // Check if token is expired
    if (Date.now() >= this.tokenExpiration) {
      throw new Error('Current token is expired');
    }
    
    return this.currentToken;
  }
  
  // Method to get token info for debugging
  getTokenInfo() {
    return {
      hasToken: !!this.currentToken,
      expiresIn: this.tokenExpiration ? (this.tokenExpiration - Date.now()) / 1000 : 0,
      expiration: this.tokenExpiration ? new Date(this.tokenExpiration) : null
    };
  }
}

// Export singleton instance
let tokenManager = null;

function getTokenManager() {
  if (!tokenManager) {
    tokenManager = new GitHubAppTokenManager();
  }
  return tokenManager;
}

module.exports = { getTokenManager, GitHubAppTokenManager };