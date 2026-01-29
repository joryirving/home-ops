#!/usr/bin/env node

const fs = require('fs');
const GitHubAppHelper = require('../../../github-app-helper.js');

// Load the configuration
const config = JSON.parse(fs.readFileSync('../../../.github_app_config.json', 'utf8'));
const githubHelper = new GitHubAppHelper(
  config.appId,
  config.privateKey,
  config.webhookSecret
);

async function updateWebhookFiles() {
  try {
    console.log('Updating webhook files using GitHub App...');
    
    // Read the current files that need to be updated
    const hooksYaml = fs.readFileSync('kubernetes/apps/base/self-hosted/webhook/resources/hooks.yaml', 'utf8');
    const processScript = fs.readFileSync('kubernetes/apps/base/self-hosted/webhook/resources/process-github-event.sh', 'utf8');
    
    console.log('Updating hooks.yaml...');
    await githubHelper.updateFile(
      'joryirving', 
      'home-ops', 
      'kubernetes/apps/base/self-hosted/webhook/resources/hooks.yaml', 
      hooksYaml,
      'feat(webhook): add GitHub event processing for bot mentions',
      'main'
    );
    
    console.log('Updating process-github-event.sh...');
    await githubHelper.updateFile(
      'joryirving', 
      'home-ops', 
      'kubernetes/apps/base/self-hosted/webhook/resources/process-github-event.sh', 
      processScript,
      'feat(webhook): add GitHub event processing for bot mentions',
      'main'
    );
    
    console.log('Files updated successfully!');
    
  } catch (error) {
    console.error('Error updating files:', error);
  }
}

updateWebhookFiles();