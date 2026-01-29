const { Octokit } = require('@octokit/rest');
const fs = require('fs');

// Load the configuration
const config = JSON.parse(fs.readFileSync('/home/node/clawd/.github_app_config.json', 'utf8'));

// Create a regular octokit instance to check repo existence
const octokit = new Octokit();

async function checkReposDirect() {
  // Test different possible repository owners
  const possibleRepos = [
    { owner: 'clawd', repo: 'home-ops' },
    { owner: 'clawd', repo: 'containers' },
    { owner: 'joryirving', repo: 'home-ops' },
    { owner: 'joryirving', repo: 'containers' },
    { owner: 'jory', repo: 'home-ops' },
    { owner: 'jory', repo: 'containers' }
  ];

  console.log('Checking repository existence...\n');

  for (const { owner, repo } of possibleRepos) {
    console.log(`Checking ${owner}/${repo}...`);

    // Check if the repository exists
    try {
      const { data } = await octokit.repos.get({
        owner,
        repo
      });
      console.log(`✓ Repository ${owner}/${repo} exists`);
      console.log(`  Full Name: ${data.full_name}`);
      console.log(`  Clone URL: ${data.clone_url}`);
      console.log(`  Private: ${data.private}`);
    } catch (error) {
      if (error.status === 404) {
        console.log(`✗ Repository ${owner}/${repo} does not exist`);
      } else {
        console.log(`✗ Error accessing ${owner}/${repo}:`, error.message);
      }
    }

    console.log(''); // Empty line for readability
  }
}

checkReposDirect();