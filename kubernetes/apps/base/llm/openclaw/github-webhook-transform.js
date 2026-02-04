// GitHub Webhook Transform for OpenClaw
const { spawn } = require('child_process');

// Import the existing GitHub App token manager (fixed version)
const { getTokenManager } = require('./github-app-token-manager.js');

/**
 * Transform function for GitHub webhook events
 * @param {Object} ctx - Context object containing payload, headers, etc.
 * @returns {Object} Response object
 */
async function transform(ctx) {
  const event = ctx.payload;
  console.log('Received GitHub webhook event:', event.action || 'unknown');

  const eventType = ctx.headers['x-github-event'];
  const deliveryId = ctx.headers['x-github-delivery'];

  console.log(`Processing ${eventType} event with delivery ID: ${deliveryId}`);

  if (eventType === 'pull_request' && event.action === 'opened') {
    // GitHub webhook payload structure has the PR data in 'pull_request' field
    const pullRequest = event.pull_request || event;
    
    // Extract PR information using proper GitHub webhook payload structure
    const prInfo = {
      repo: event.repository?.full_name || `${event.organization?.login}/${event.repository?.name}`,
      pr_number: pullRequest?.number || event.number,
      title: pullRequest?.title,
      description: pullRequest?.body || pullRequest?.description || '',
      author: pullRequest?.user?.login || event.sender?.login || 'unknown',
      url: pullRequest?.html_url,
      created_at: pullRequest?.created_at || pullRequest?.created_at
    };

    console.log(`New PR #${prInfo.pr_number} opened: ${prInfo.title}`);

    // Validate that we have the required information
    if (!prInfo.repo || !prInfo.pr_number) {
      console.error('Missing required PR information:', prInfo);
      console.error('Full event object:', JSON.stringify(event, null, 2));
      return {
        message: `Error: Missing required PR information. Repo: ${prInfo.repo}, PR Number: ${prInfo.pr_number}`,
        channel: "last"
      };
    }

    // Prepare the message to send to the grumpy-sysadmin agent
    const agentMessage = `Please review this newly opened pull request: ${prInfo.repo}#${prInfo.pr_number}\n\nTitle: ${prInfo.title}\n\nDescription: ${prInfo.description}\n\nURL: ${prInfo.url}\n\nThis agent should review the PR and post a review directly to GitHub using the GitHub App authentication.`;
    
    // Spawn the grumpy sysadmin agent to review the PR
    return {
      message: agentMessage,
      agent: "grumpy-sysadmin",
      channel: "last",
      metadata: {
        repo: prInfo.repo,
        pr_number: prInfo.pr_number,
        event_type: eventType,
        delivery_id: deliveryId,
        pr_info: prInfo
      }
    };
  }
  else if (eventType === 'pull_request' && ['closed', 'merged'].includes(event.action)) {
    const pullRequest = event.pull_request || event;
    const action = event.action === 'merged' ? 'merged' : 'closed';
    
    console.log(`PR #${pullRequest?.number} ${action}: ${pullRequest?.title}`);

    return {
      message: `Pull request #${event.repository?.full_name}/${pullRequest?.number} was ${action}`,
      channel: "last"
    };
  }
  else {
    // For other events, return a simple acknowledgment
    return {
      message: `Received ${eventType} event: ${event.action || 'unknown'}`,
      channel: "last"
    };
  }
}

module.exports = transform;