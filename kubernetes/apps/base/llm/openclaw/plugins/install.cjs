'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const cli = process.env.PLUGIN_INSTALL_CLI || '/app/dist/index.js';
const root = process.env.PLUGIN_STAGE_ROOT || '/home/node/.openclaw/plugin-stage';
const inventory = JSON.parse(fs.readFileSync(path.join(__dirname, 'inventory.json'), 'utf8'));
const hostVersion = execFileSync(process.execPath, [cli, '--version'], { encoding: 'utf8' }).trim().match(/\d{4}\.\d+\.\d+(?:[-.][\w.-]+)?/)[0];
const active = path.join(root, 'active');
fs.mkdirSync(active, { recursive: true });
for (const plugin of inventory) {
  if (!/^[a-z0-9-]+$/.test(plugin.id) || !/^(npm:|clawhub:).+@[^@]+$/.test(plugin.source)) {
    throw new Error('Invalid pinned plugin inventory entry: ' + plugin.id);
  }
  const source = plugin.source.replace('{hostVersion}', hostVersion);
  // Immutable generations retain prior artifacts for rollback; the live Gateway's state is never opened.
  const key = crypto.createHash('sha256').update(JSON.stringify({ source, hostVersion, installer: 1 })).digest('hex').slice(0, 20);
  const stage = path.join(root, 'generations', plugin.id, key);
  const config = path.join(stage, 'installer.json');
  const receipt = path.join(stage, 'receipt.json');
  fs.mkdirSync(stage, { recursive: true });
  const env = { ...process.env, OPENCLAW_STATE_DIR: stage, OPENCLAW_CONFIG_PATH: config, OPENCLAW_CONFIG_READONLY: '0', OPENCLAW_NIX_MODE: '0' };
  function run(args) {
    return execFileSync(process.execPath, [cli, ...args], { env, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  }
  let artifact;
  if (fs.existsSync(receipt)) {
    const saved = JSON.parse(fs.readFileSync(receipt, 'utf8'));
    if (saved.source !== source || saved.hostVersion !== hostVersion) throw new Error('Receipt mismatch: ' + plugin.id);
    artifact = saved.artifact;
  } else {
    if (!fs.existsSync(config)) fs.writeFileSync(config, '{}\n', { mode: 0o600 });
    console.log('Installing ' + source);
    console.log(run(['plugins', 'install', source, '--pin', '--accept-capabilities', '--acknowledge-install-policy-warning']));
  }
  const listed = JSON.parse(run(['plugins', 'list', '--json']));
  const installed = listed.plugins.find(entry => entry.id === plugin.id && entry.status === 'loaded');
  if (!installed || !installed.rootDir) throw new Error('Plugin did not load: ' + plugin.id);
  if (artifact && artifact !== installed.rootDir) throw new Error('Artifact path changed: ' + plugin.id);
  artifact = installed.rootDir;
  const realStage = fs.realpathSync(stage) + path.sep;
  if (!fs.realpathSync(artifact).startsWith(realStage)) throw new Error('Artifact escaped staging root');
  fs.writeFileSync(receipt, JSON.stringify({ source, hostVersion, artifact }) + '\n');
  const target = path.join(active, plugin.id);
  const temporary = target + '.next';
  fs.rmSync(temporary, { force: true });
  fs.symlinkSync(artifact, temporary, 'dir');
  fs.renameSync(temporary, target);
  console.log('Ready: ' + plugin.id);
}
