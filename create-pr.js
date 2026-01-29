#!/usr/bin/env node

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
 * Creates a PR in the specified repository
 * Usage: node create-pr.js <owner> <repo> <title> <body> <head_branch> [base_branch]
 */
async function createPRCLI() {
  const args = process.argv.slice(2);
  
  if (args.length < 5) {
    console.log('Usage: node create-pr.js <owner> <repo> <title> <body> <head_branch> [base_branch]');
    console.log('Example: node create-pr.js joryirving home-ops "Update config" "Updated the deployment config" feature/update-config main');
    process.exit(1);
  }
  
  const [owner, repo, title, body, head, base = 'main'] = args;
  
  console.log(`Creating PR in ${owner}/${repo}...`);
  console.log(`Title: ${title}`);
  console.log(`Branch: ${head} -> ${base}`);
  
  try {
    const pr = await githubHelper.createPR(owner, repo, title, body, head, base);
    console.log(`✓ Successfully created PR #${pr.number}: ${pr.title}`);
    console.log(`URL: ${pr.html_url}`);
  } catch (error) {
    console.error('✗ Error creating PR:', error.message);
    process.exit(1);
  }
}

// If this file is run directly, execute the CLI function
if (require.main === module) {
  createPRCLI();
}

module.exports = { githubHelper, createPR: githubHelper.createPR };