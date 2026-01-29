const fs = require('fs');
const GitHubAppHelper = require('./github-app-helper.js');

// Load the configuration
const config = JSON.parse(fs.readFileSync('/home/node/clawd/.github_app_config.json', 'utf8'));

async function testConnection() {
  const githubHelper = new GitHubAppHelper(
    config.appId,
    config.privateKey,
    config.webhookSecret
  );

  try {
    console.log('Testing GitHub App connection...');
    
    // Get all installations for this app
    const installations = await githubHelper.getInstallations();
    console.log('Found', installations.length, 'installations:');
    
    installations.forEach((installation, index) => {
      console.log(`${index + 1}. Account: ${installation.account.login} (${installation.account.type})`);
      console.log(`   Installation ID: ${installation.id}`);
      if (installation.suspended_at) {
        console.log('   Status: SUSPENDED');
      } else {
        console.log('   Status: ACTIVE');
      }
    });
    
    // Check if our target repos are available
    const targetRepos = [
      { owner: 'clawd', repo: 'home-ops' },
      { owner: 'clawd', repo: 'containers' }
    ];
    
    for (const { owner, repo } of targetRepos) {
      console.log(`\nChecking installation for ${owner}/${repo}...`);
      try {
        const installation = await githubHelper.getInstallationForRepo(owner, repo);
        if (installation) {
          console.log(`✓ GitHub App is installed on ${owner}/${repo}`);
          console.log(`  Installation ID: ${installation.id}`);
          console.log(`  Account: ${installation.account.login}`);
        } else {
          console.log(`✗ GitHub App is NOT installed on ${owner}/${repo}`);
          console.log(`  Please install your GitHub App on this repository.`);
        }
      } catch (error) {
        console.log(`✗ Error checking ${owner}/${repo}:`, error.message);
      }
    }
    
    console.log('\nTest completed successfully!');
  } catch (error) {
    console.error('Error during testing:', error);
  }
}

testConnection();