// Grumpy Sysadmin Agent for GitHub PR Reviews
const { spawn } = require('child_process');

// Import the GitHub App token manager
const { getTokenManager } = require('./github-app-token-manager.js');

/**
 * Process a pull request review request
 * @param {Object} context - The context containing PR information
 * @param {Object} metadata - Metadata from the webhook
 */
async function processPRReview(context, metadata) {
  console.log('Grumpy Sysadmin Agent: Processing PR review request');
  
  // Extract PR information from context or metadata
  const prInfo = metadata?.pr_info || {};
  const repo = prInfo.repo || context.repo;
  const prNumber = prInfo.pr_number || context.pr_number;
  
  if (!repo || !prNumber) {
    console.error('Missing required PR information:', { repo, prNumber, prInfo, metadata });
    return 'Error: Missing required PR information for review';
  }
  
  console.log(`Reviewing PR #${prNumber} in ${repo}`);
  
  try {
    // Get the token manager and token for GitHub API access
    const tokenManager = await getTokenManager();
    const githubToken = await tokenManager.getToken();
    
    // Fetch the PR details from GitHub API
    const prResponse = await fetch(`https://api.github.com/repos/${repo}/pulls/${prNumber}`, {
      headers: {
        'Authorization': `Bearer ${githubToken}`,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'OpenClaw-GitHub-App'
      }
    });
    
    if (!prResponse.ok) {
      throw new Error(`Failed to fetch PR: ${prResponse.status} - ${await prResponse.text()}`);
    }
    
    const prDetails = await prResponse.json();
    
    // Fetch the PR files to analyze changes
    const filesResponse = await fetch(`https://api.github.com/repos/${repo}/pulls/${prNumber}/files`, {
      headers: {
        'Authorization': `Bearer ${githubToken}`,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'OpenClaw-GitHub-App'
      }
    });
    
    if (!filesResponse.ok) {
      console.warn('Could not fetch PR files:', await filesResponse.text());
    }
    
    const files = filesResponse.ok ? await filesResponse.json() : [];
    
    // Perform grumpy sysadmin review
    const reviewComment = generateGrumpyReview(prDetails, files);
    
    // Post the review comment to the PR
    const commentResponse = await fetch(`https://api.github.com/repos/${repo}/issues/${prNumber}/comments`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${githubToken}`,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'OpenClaw-GitHub-App',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        body: reviewComment
      })
    });
    
    if (!commentResponse.ok) {
      throw new Error(`Failed to post review comment: ${commentResponse.status} - ${await commentResponse.text()}`);
    }
    
    console.log(`Successfully posted review to PR #${prNumber}`);
    
    return `Grumpy Sysadmin Agent: Successfully posted review to PR #${prNumber} in ${repo}`;
    
  } catch (error) {
    console.error('Error in PR review process:', error.message);
    return `Error posting PR review: ${error.message}`;
  }
}

/**
 * Generate a grumpy sysadmin-style review based on PR details
 * @param {Object} prDetails - The PR details from GitHub API
 * @param {Array} files - Array of files changed in the PR
 * @returns {string} The review comment
 */
function generateGrumpyReview(prDetails, files) {
  const { title, user, created_at, body, html_url } = prDetails;
  const fileCount = files.length;
  const additions = files.reduce((sum, file) => sum + (file.additions || 0), 0);
  const deletions = files.reduce((sum, file) => sum + (file.deletions || 0), 0);
  
  // Generate a grumpy but constructive review
  let review = `## ⚠️ Grumpy Sysadmin Review for PR #${prDetails.number}

Hello @${user.login}, 

As your resident grumpy sysadmin, I've reviewed your pull request "${title}". Here are my observations:

### 📋 Summary
- **Author**: @${user.login}
- **Created**: ${created_at}
- **Files Changed**: ${fileCount}
- **Additions**: ${additions}
- **Deletions**: ${deletions}

### 🔍 Technical Assessment
`;

  // Add some grumpy but helpful commentary based on the changes
  if (fileCount > 10) {
    review += `- **⚠️ Large PR**: This PR touches ${fileCount} files. Could this be broken down into smaller, more focused changes?\n`;
  }
  
  if (additions > 200) {
    review += `- **⚠️ Code Volume**: This PR adds ${additions} lines. Please ensure adequate testing.\n`;
  }
  
  if (!body || body.trim().length < 20) {
    review += `- **⚠️ Description**: The PR description is quite brief. Please provide more context about *why* these changes are needed.\n`;
  }
  
  // Check for common infrastructure files that might need special attention
  const sensitiveFiles = files.filter(file => 
    file.filename.includes('k8s') || 
    file.filename.includes('yaml') || 
    file.filename.includes('yml') ||
    file.filename.includes('config') ||
    file.filename.includes('secret')
  );
  
  if (sensitiveFiles.length > 0) {
    review += `- **🚨 Sensitive Areas**: This PR touches infrastructure/configuration files (${sensitiveFiles.map(f => f.filename).join(', ')}). Extra scrutiny required!\n`;
  }
  
  // If no specific issues found, add general grumpiness
  if (review.split('\n').filter(line => line.startsWith('-')).length === 0) {
    review += `- **🔍 General**: Changes look reasonable, but please ensure all tests pass and consider edge cases.\n`;
  }
  
  review += `
### ✅ Approval Criteria
Before this PR can be merged, please ensure:

1. All CI checks are passing
2. Changes have been tested in a staging environment
3. Documentation has been updated if applicable
4. Another team member has reviewed this code

### 📝 Final Thoughts
Thanks for your contribution to the infrastructure. Remember: "With great power comes great responsibility." Please make sure you understand the implications of these changes before merging.

Yours grumpily,  
The Grumpy Sysadmin 🤖

*This review was automatically generated by the Grumpy Sysadmin Agent.*
`;

  return review;
}

/**
 * Main function to handle the agent task
 * @param {Object} context - The context object
 * @param {Object} options - Additional options
 */
async function handleAgentTask(context, options = {}) {
  try {
    console.log('Grumpy Sysadmin Agent activated');
    
    // Check if this is a PR review request
    if (context.message && 
        (context.message.toLowerCase().includes('review') || 
         context.message.toLowerCase().includes('pull request') ||
         context.metadata?.pr_number)) {
      
      return await processPRReview(context, context.metadata);
    }
    
    // Default response for other requests
    return "Grumpy Sysadmin Agent: I specialize in reviewing pull requests. Please provide PR details for review.";
    
  } catch (error) {
    console.error('Grumpy Sysadmin Agent error:', error.message);
    return `Grumpy Sysadmin Agent Error: ${error.message}`;
  }
}

module.exports = { handleAgentTask, processPRReview, generateGrumpyReview };