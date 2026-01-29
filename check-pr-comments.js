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

async function getPRComments() {
  try {
    // First, get installation for joryirving/home-ops
    const installation = await githubHelper.getInstallationForRepo('joryirving', 'home-ops');
    if (!installation) {
      console.log('GitHub App is not installed on joryirving/home-ops');
      return;
    }

    // Create a new octokit instance with installation token
    const installationOctokit = await githubHelper.getInstallationOctokit(installation.id);

    // Get comments on PR #5779 (the terraform documentation PR)
    const { data: comments } = await installationOctokit.issues.listComments({
      owner: 'joryirving',
      repo: 'home-ops',
      issue_number: 5779,
      per_page: 30
    });

    console.log('Comments on PR #5779 (Terraform documentation PR):');
    if (comments.length === 0) {
      console.log('No comments found on this PR.');
    } else {
      for (const comment of comments) {
        console.log(`Comment by ${comment.user.login} on ${comment.created_at}:`);
        console.log(comment.body.substring(0, 200) + (comment.body.length > 200 ? '...' : ''));
        console.log('---');
      }
    }

    // Also get the PR details
    const { data: pr } = await installationOctokit.pulls.get({
      owner: 'joryirving',
      repo: 'home-ops',
      pull_number: 5779
    });

    console.log(`\nPR Details:`);
    console.log(`Title: ${pr.title}`);
    console.log(`State: ${pr.state}`);
    console.log(`Created: ${pr.created_at}`);
    console.log(`Updated: ${pr.updated_at}`);
    console.log(`Branch: ${pr.head.ref} → ${pr.base.ref}`);
    console.log(`Body: ${pr.body ? pr.body.substring(0, 200) + (pr.body.length > 200 ? '...' : '') : 'No description'}`);

  } catch (error) {
    console.error('Error fetching PR comments:', error);
  }
}

getPRComments();