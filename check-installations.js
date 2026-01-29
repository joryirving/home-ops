const fs = require('fs');
const GitHubAppHelper = require('./github-app-helper.js');

// Load the configuration
const config = JSON.parse(fs.readFileSync('/home/node/clawd/.github_app_config.json', 'utf8'));

async function checkInstallations() {
  const githubHelper = new GitHubAppHelper(
    config.appId,
    config.privateKey,
    config.webhookSecret
  );

  // Check the correct repositories
  const repos = [
    { owner: 'joryirving', repo: 'home-ops' },
    { owner: 'joryirving', repo: 'containers' }
  ];

  console.log('Checking GitHub App installations...\n');

  for (const { owner, repo } of repos) {
    console.log(`Checking installation for ${owner}/${repo}...`);
    try {
      const installation = await githubHelper.getInstallationForRepo(owner, repo);
      if (installation) {
        console.log(`✓ GitHub App is installed on ${owner}/${repo}`);
        console.log(`  Installation ID: ${installation.id}`);
        console.log(`  Account: ${installation.account.login}`);
        console.log(`  Permissions:`, installation.permissions);
      } else {
        console.log(`✗ GitHub App is NOT installed on ${owner}/${repo}`);
        console.log(`  Please install your GitHub App on this repository.`);
      }
    } catch (error) {
      console.log(`✗ Error checking ${owner}/${repo}:`, error.message);
    }
    console.log('');
  }
}

checkInstallations();