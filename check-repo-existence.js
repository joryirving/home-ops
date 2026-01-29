const fs = require('fs');
const GitHubAppHelper = require('./github-app-helper.js');

// Load the configuration
const config = JSON.parse(fs.readFileSync('/home/node/clawd/.github_app_config.json', 'utf8'));

async function checkRepoExistence() {
  const githubHelper = new GitHubAppHelper(
    config.appId,
    config.privateKey,
    config.webhookSecret
  );

  // Test different possible repository owners
  const possibleRepos = [
    { owner: 'clawd', repo: 'home-ops' },
    { owner: 'clawd', repo: 'containers' },
    { owner: 'joryirving', repo: 'home-ops' },
    { owner: 'joryirving', repo: 'containers' },
    { owner: 'jory', repo: 'home-ops' },
    { owner: 'jory', repo: 'containers' }
  ];

  console.log('Checking repository existence and app installation...\n');

  for (const { owner, repo } of possibleRepos) {
    console.log(`Checking ${owner}/${repo}...`);

    // First, check if the repository exists
    try {
      await githubHelper.octokit.repos.get({
        owner,
        repo
      });
      console.log(`✓ Repository ${owner}/${repo} exists`);
    } catch (error) {
      if (error.status === 404) {
        console.log(`✗ Repository ${owner}/${repo} does not exist`);
        continue; // Skip to next repo
      } else {
        console.log(`✗ Error accessing ${owner}/${repo}:`, error.message);
        continue; // Skip to next repo
      }
    }

    // Check if the app is installed on this repository
    try {
      const installation = await githubHelper.getInstallationForRepo(owner, repo);
      if (installation) {
        console.log(`✓ GitHub App is installed on ${owner}/${repo}`);
        console.log(`  Installation ID: ${installation.id}`);
      } else {
        console.log(`✗ GitHub App is NOT installed on ${owner}/${repo}`);
      }
    } catch (error) {
      console.log(`✗ Error checking installation for ${owner}/${repo}:`, error.message);
    }

    console.log(''); // Empty line for readability
  }
}

checkRepoExistence();