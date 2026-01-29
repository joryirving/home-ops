const fs = require('fs');
const GitHubAppHelper = require('./github-app-helper.js');

// Load the configuration
const config = JSON.parse(fs.readFileSync('/home/node/clawd/.github_app_config.json', 'utf8'));
const githubHelper = new GitHubAppHelper(
  config.appId,
  config.privateKey,
  config.webhookSecret
);

/**
 * Convenience function to create a PR in the home-ops repository
 */
async function createHomeOpsPR(title, body, head, base = 'main') {
  return await githubHelper.createPR('joryirving', 'home-ops', title, body, head, base);
}

/**
 * Convenience function to create a PR in the containers repository
 */
async function createContainersPR(title, body, head, base = 'main') {
  return await githubHelper.createPR('joryirving', 'containers', title, body, head, base);
}

/**
 * Generic function to create a PR in any repository
 */
async function createPR(owner, repo, title, body, head, base = 'main') {
  return await githubHelper.createPR(owner, repo, title, body, head, base);
}

module.exports = {
  githubHelper,
  createHomeOpsPR,
  createContainersPR,
  createPR
};