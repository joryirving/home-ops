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

async function listOpenPRs() {
  try {
    // First, get installation for joryirving/home-ops
    const installation = await githubHelper.getInstallationForRepo('joryirving', 'home-ops');
    if (!installation) {
      console.log('GitHub App is not installed on joryirving/home-ops');
      return;
    }

    // Create a new octokit instance with installation token
    const installationOctokit = await githubHelper.getInstallationOctokit(installation.id);

    // Get open pull requests
    const { data: pulls } = await installationOctokit.pulls.list({
      owner: 'joryirving',
      repo: 'home-ops',
      state: 'open'
    });

    console.log('Open Pull Requests:');
    if (pulls.length === 0) {
      console.log('No open pull requests found.');
    } else {
      for (const pr of pulls) {
        console.log(`- #${pr.number}: ${pr.title} (${pr.state})`);
        console.log(`  URL: ${pr.html_url}`);
        console.log(`  Created: ${pr.created_at}`);
        console.log(`  Branch: ${pr.head.ref} → ${pr.base.ref}`);
        console.log('');
      }
    }

    // Also check for recently closed PRs in case they were just merged
    const { data: closedPulls } = await installationOctokit.pulls.list({
      owner: 'joryirving',
      repo: 'home-ops',
      state: 'closed',
      sort: 'updated',
      direction: 'desc',
      per_page: 10
    });

    console.log('Recently Closed/Merged Pull Requests (top 10):');
    for (const pr of closedPulls.slice(0, 5)) {
      console.log(`- #${pr.number}: ${pr.title} (${pr.state})`);
      console.log(`  URL: ${pr.html_url}`);
      console.log(`  Updated: ${pr.updated_at}`);
      console.log(`  Branch: ${pr.head.ref} → ${pr.base.ref}`);
      console.log('');
    }

  } catch (error) {
    console.error('Error fetching PRs:', error);
  }
}

listOpenPRs();