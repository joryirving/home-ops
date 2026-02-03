// GitHub Webhook Transform for OpenClaw
const { spawn } = require('child_process');

/**
 * Transform function for GitHub webhook events
 * @param {Object} event - The incoming webhook event
 * @param {Object} context - Context containing headers, etc.
 * @returns {Object} Response object
 */
async function transform(event, context) {
  console.log('Received GitHub webhook event:', event.action || 'unknown');
  
  const eventType = context.headers['x-github-event'];
  const deliveryId = context.headers['x-github-delivery'];
  
  console.log(`Processing ${eventType} event with delivery ID: ${deliveryId}`);
  
  if (eventType === 'pull_request' && event.action === 'opened') {
    console.log(`New PR #${event.number} opened: ${event.title}`);
    
    // Prepare the PR information for the review agent
    const prInfo = {
      repo: event.repository.full_name,
      pr_number: event.number,
      title: event.title,
      description: event.body || '',
      author: event.user.login,
      url: event.pull_request.html_url,
      created_at: event.pull_request.created_at
    };
    
    // Spawn the grumpy sysadmin agent to review the PR
    const agentMessage = `Please review this newly opened pull request: ${prInfo.repo}#${prInfo.pr_number}\n\nTitle: ${prInfo.title}\n\nDescription: ${prInfo.description}\n\nURL: ${prInfo.url}`;
    
    // Send the message to the agent via OpenClaw's wake mechanism
    return {
      wake: {
        message: agentMessage,
        agent: "grumpy-sysadmin",
        channel: "github",
        metadata: {
          repo: prInfo.repo,
          pr_number: prInfo.pr_number,
          event_type: eventType,
          delivery_id: deliveryId
        }
      }
    };
  } 
  else if (eventType === 'pull_request' && ['closed', 'merged'].includes(event.action)) {
    const action = event.action === 'merged' ? 'merged' : 'closed';
    console.log(`PR #${event.number} ${action}: ${event.title}`);
    
    // Optionally notify about closed/merged PRs
    return {
      message: `Pull request #${event.repository.full_name}/${event.number} was ${action}`
    };
  }
  else {
    // For other events, return a simple acknowledgment
    return {
      message: `Received ${eventType} event: ${event.action || 'unknown'}`
    };
  }
}

module.exports = { transform };