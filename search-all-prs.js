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

async function searchPRs() {
  try {
    // First, get installation for joryirving/home-ops
    const installation = await githubHelper.getInstallationForRepo('joryirving', 'home-ops');
    if (!installation) {
      console.log('GitHub App is not installed on joryirving/home-ops');
      return;
    }

    // Create a new octokit instance with installation token
    const installationOctokit = await githubHelper.getInstallationOctokit(installation.id);

    // Get all pull requests (open and closed) to find any related to webhooks
    const { data: allPulls } = await installationOctokit.pulls.list({
      owner: 'joryirving',
      repo: 'home-ops',
      state: 'all',
      sort: 'updated',
      direction: 'desc',
      per_page: 30
    });

    console.log('All Pull Requests (most recent first):');
    for (const pr of allPulls) {
      const lowerTitle = pr.title.toLowerCase();
      const hasWebhook = lowerTitle.includes('webhook');
      const hasTerraform = lowerTitle.includes('terraform');
      
      console.log(`${hasWebhook ? '[WEBHOOK]' : hasTerraform ? '[TF]' : '       '} #${pr.number}: ${pr.title} (${pr.state})`);
      console.log(`  URL: ${pr.html_url}`);
      console.log(`  Updated: ${pr.updated_at}`);
      console.log(`  Branch: ${pr.head.ref} → ${pr.base.ref}`);
      
      if (hasWebhook) {
        // Get comments on this webhook-related PR
        try {
          const { data: comments } = await installationOctokit.issues.listComments({
            owner: 'joryirving',
            repo: 'home-ops',
            issue_number: pr.number,
            per_page: 10
          });
          
          if (comments.length > 0) {
            console.log(`  Recent comments: ${comments.length}`);
            for (let i = 0; i < Math.min(2, comments.length); i++) {
              const comment = comments[i];
              console.log(`    - ${comment.user.login}: ${comment.body.substring(0, 80)}${comment.body.length > 80 ? '...' : ''}`);
            }
          }
        } catch (commentErr) {
          console.log(`  Could not fetch comments: ${commentErr.message}`);
        }
      }
      console.log('');
    }

  } catch (error) {
    console.error('Error fetching PRs:', error);
  }
}

searchPRs();