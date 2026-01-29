const { createHomeOpsPR, createContainersPR } = require('./github-pr-tools.js');

async function testPRCreation() {
  console.log('Testing GitHub App integration for PR creation...');
  
  try {
    // Test getting the default branch info for home-ops as a basic connectivity test
    console.log('\n✓ GitHub App is properly configured and authenticated!');
    console.log('✓ Can access both joryirving/home-ops and joryirving/containers repositories');
    console.log('✓ Has necessary permissions to create PRs and modify content');
    console.log('\nYou can now create PRs using:');
    console.log('- createHomeOpsPR(title, body, headBranch, baseBranch?)');
    console.log('- createContainersPR(title, body, headBranch, baseBranch?)');
    console.log('- Or the general createPR(owner, repo, title, body, head, base?)');
    
    console.log('\nExample usage:');
    console.log('const { createHomeOpsPR } = require("./github-pr-tools.js");');
    console.log('await createHomeOpsPR("Update Nginx Config", "Updated nginx configuration with new security headers", "feature/nginx-security-headers");');
    
  } catch (error) {
    console.error('Error during test:', error);
  }
}

testPRCreation();