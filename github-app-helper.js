const { createAppAuth } = require('@octokit/auth-app');
const { Octokit } = require('@octokit/rest');

class GitHubAppHelper {
  constructor(appId, privateKey, webhookSecret) {
    this.appId = appId;
    this.privateKey = privateKey;
    this.webhookSecret = webhookSecret;
    
    this.auth = createAppAuth({
      appId: this.appId,
      privateKey: this.privateKey,
      webhookSecret: this.webhookSecret
    });
    
    this.octokit = new Octokit({
      authStrategy: createAppAuth,
      auth: {
        appId: this.appId,
        privateKey: this.privateKey,
        webhookSecret: this.webhookSecret
      }
    });
  }

  async getInstallations() {
    try {
      const { data } = await this.octokit.apps.listInstallations();
      return data;
    } catch (error) {
      console.error('Error fetching installations:', error);
      throw error;
    }
  }

  async getInstallationForRepo(owner, repo) {
    try {
      const { data } = await this.octokit.apps.getRepoInstallation({
        owner,
        repo
      });
      return data;
    } catch (error) {
      if (error.status === 404) {
        console.log(`GitHub App is not installed on ${owner}/${repo}`);
        return null;
      }
      console.error('Error fetching repository installation:', error);
      throw error;
    }
  }

  // Create a new octokit instance with the installation token
  async getInstallationOctokit(installationId) {
    const installationAuth = await this.auth({
      type: "installation",
      installationId: installationId
    });
    
    return new Octokit({
      auth: installationAuth.token
    });
  }

  async createPR(owner, repo, title, body, head, base = 'main') {
    try {
      // First, get the installation ID for this repository
      const installation = await this.getInstallationForRepo(owner, repo);
      if (!installation) {
        throw new Error(`GitHub App is not installed on ${owner}/${repo}. Please install the app first.`);
      }

      // Create a new octokit instance with installation token
      const installationOctokit = await this.getInstallationOctokit(installation.id);

      // Create the PR
      const { data } = await installationOctokit.pulls.create({
        owner,
        repo,
        title,
        body,
        head, // branch name to merge from
        base  // branch name to merge to (default: main)
      });

      return data;
    } catch (error) {
      console.error('Error creating PR:', error);
      throw error;
    }
  }

  async createBranch(owner, repo, branchName, baseSha) {
    try {
      // Get installation first
      const installation = await this.getInstallationForRepo(owner, repo);
      if (!installation) {
        throw new Error(`GitHub App is not installed on ${owner}/${repo}. Please install the app first.`);
      }

      const installationOctokit = await this.getInstallationOctokit(installation.id);

      const { data } = await installationOctokit.git.createRef({
        owner,
        repo,
        ref: `refs/heads/${branchName}`,
        sha: baseSha
      });
      
      return data;
    } catch (error) {
      console.error('Error creating branch:', error);
      throw error;
    }
  }

  async getFile(owner, repo, path, ref = 'main') {
    try {
      // Get installation first
      const installation = await this.getInstallationForRepo(owner, repo);
      if (!installation) {
        throw new Error(`GitHub App is not installed on ${owner}/${repo}. Please install the app first.`);
      }

      const installationOctokit = await this.getInstallationOctokit(installation.id);

      const { data } = await installationOctokit.repos.getContent({
        owner,
        repo,
        path,
        ref
      });
      
      return data;
    } catch (error) {
      console.error('Error getting file:', error);
      throw error;
    }
  }

  async updateFile(owner, repo, path, content, commitMessage, branch) {
    try {
      // Get installation first
      const installation = await this.getInstallationForRepo(owner, repo);
      if (!installation) {
        throw new Error(`GitHub App is not installed on ${owner}/${repo}. Please install the app first.`);
      }

      const installationOctokit = await this.getInstallationOctokit(installation.id);

      // Get the current file to get its SHA
      let fileData;
      try {
        fileData = await this.getFile(owner, repo, path, branch);
      } catch (error) {
        // File doesn't exist, we'll create it
        fileData = null;
      }

      const params = {
        owner,
        repo,
        path,
        message: commitMessage,
        content: Buffer.from(content).toString('base64'),
        branch
      };

      if (fileData && fileData.sha) {
        params.sha = fileData.sha;
      }

      const { data } = await installationOctokit.repos.createOrUpdateFileContents(params);
      return data;
    } catch (error) {
      console.error('Error updating file:', error);
      throw error;
    }
  }
}

module.exports = GitHubAppHelper;