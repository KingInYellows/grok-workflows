import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const consumers = ['graphite-stack-review.rhai', 'graphite-pr-review.rhai', 'linear-cycle-deliver.rhai', 'ship-next-issue.rhai'];
const launcher = name => JSON.parse(read(name).match(/fn support_cli\(\) \{\s*("(?:[^"\\]|\\.)*")\s*\}/)[1]);
const fixture = t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'grok portable '));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const run = (command, args, env) => {
  const result = spawnSync(command, args, { cwd: root, env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout;
};

test('custom GROK_HOME installs workflows and executable helpers; launcher handles spaces and arguments', t => {
  const dir = fixture(t);
  const home = path.join(dir, 'host home');
  const grokHome = path.join(dir, 'custom config');
  const extra = path.join(dir, 'explicit Windows home');
  const env = { ...process.env, HOME: home, GROK_HOME: grokHome };
  run('bash', ['sync-workflows.sh', '--destination', extra], env);
  for (const dest of [grokHome, extra]) {
    assert.ok(fs.existsSync(path.join(dest, 'workflows/graphite-pr-review.rhai')));
    assert.ok(fs.existsSync(path.join(dest, 'workflow-support/graphite-stack-review/lib.mjs')));
    assert.ok(!fs.existsSync(path.join(dest, 'workflow-support/graphite-stack-review/parse.test.mjs')));
  }
  assert.ok(!fs.existsSync(path.join(home, '.grok')));
  for (const name of consumers) {
    const result = JSON.parse(run('bash', ['-c', `node ${launcher(name)} help`], env));
    assert.equal(result.ok, true);
    assert.match(result.usage, /poll/);
  }
  const missing = spawnSync('bash', ['-c', `node ${launcher(consumers[0])} help`], { env: { ...env, GROK_HOME: path.join(dir, 'missing') }, encoding: 'utf8' });
  assert.notEqual(missing.status, 0);
  const state = run(process.execPath, ['--input-type=module', '-e', `import {SUPPORT_DIR} from ${JSON.stringify(new URL('../workflow-support/graphite-stack-review/lib.mjs', import.meta.url).href)}; console.log(SUPPORT_DIR)`], env).trim();
  assert.equal(state, path.join(grokHome, 'workflow-support/graphite-stack-review'));
});

test('default home, dry-run, repeat installation, and workflow-only prune are isolated', t => {
  const dir = fixture(t);
  const env = { ...process.env, HOME: dir };
  delete env.GROK_HOME;
  const extra = path.join(dir, 'not installed');
  const preview = run('bash', ['sync-workflows.sh', '--dry-run', '--destination', extra], env);
  assert.match(preview, /cli\.mjs/);
  assert.ok(!fs.existsSync(extra));
  assert.ok(!fs.existsSync(path.join(dir, '.grok')));
  run('bash', ['sync-workflows.sh'], env);
  const dest = path.join(dir, '.grok');
  const stale = path.join(dest, 'workflows/local-only.rhai');
  const checkpoint = path.join(dest, 'workflow-support/graphite-stack-review/local-state.json');
  fs.writeFileSync(stale, 'local'); fs.writeFileSync(checkpoint, 'state');
  run('bash', ['sync-workflows.sh'], env);
  assert.ok(fs.existsSync(stale));
  run('bash', ['sync-workflows.sh', '--prune'], env);
  assert.ok(!fs.existsSync(stale));
  assert.equal(fs.readFileSync(checkpoint, 'utf8'), 'state');
  const invalid = spawnSync('bash', ['sync-workflows.sh', '--destination'], { cwd: root, env });
  assert.equal(invalid.status, 2);
});

test('portable helper contract is consistent; no cross-account or hardcoded WSL discovery', () => {
  for (const name of consumers) assert.equal(launcher(name), launcher(consumers[0]));
  assert.doesNotMatch(read('sync-workflows.sh'), /\/mnt\/c\/Users\/\*/);
  assert.doesNotMatch(read('sync-workflows.ps1'), /Ubuntu-24\.04|wsl -d/);
  assert.match(read('sync-workflows.ps1'), /\$env:GROK_HOME/);
  assert.match(read('sync-workflows.ps1'), /\[string\[\]\]\$Destination/);
  assert.doesNotMatch(read('graphite-stack-merge.rhai'), /cli\.py/);
  assert.match(read('graphite-stack-merge.rhai'), /Discovery is read-only/);
  assert.match(read('graphite-stack-merge.rhai'), /cfg.start_branch != "" && disc.tip_branch != cfg.start_branch/);
  assert.match(read('graphite-stack-merge.rhai'), /if disc.prs.len\(\) == 0/);
  assert.match(read('graphite-stack-merge.rhai'), /from_pr is not in the verified ancestry chain/);
});

test('recovery contracts retain owned-freeze handoff, missing-ID guard and explicit fresh-run guidance', () => {
  const pr = read('graphite-pr-review.rhai');
  assert.match(pr, /"required": \[[^\n]*"frozen_children"/);
  assert.match(pr, /frozen_children: frozen_children,\s*cleanup_journal: cleanup_journal/);
  assert.match(pr, /originally_frozen=false/);
  assert.match(pr, /Skip entries with restored=true: ownership ended/);
  assert.match(pr, /originally_frozen=false and restored=false/);
  assert.match(pr, /label: "restore-owned-freezes"/);
  assert.ok(pr.indexOf('label: "restore-owned-freezes"') > pr.indexOf('let submitted = agent('));
  assert.match(pr, /missing, unreadable, or inconsistent journal is a blocker/);
  const isolated = read('implement-approved-plan.rhai');
  assert.ok(isolated.indexOf('Implementation returned no resumable agent ID') < isolated.indexOf('let test_r = agent('));
  assert.match(isolated, /test_opts.resume_from = impl_r.agent_id;/);
  for (const name of ['export-workflows.rhai', 'multi-track-goal-plan.rhai', 'multi-track-plan.rhai', 'search-and-destroy.rhai', 'implement-from-plan.rhai', 'multi-track-ship.rhai']) {
    assert.doesNotMatch(read(name), /Resume to retry|sources and resume|Resume or re-run/);
  }
  const cycle = read('linear-cycle-deliver.rhai');
  assert.match(cycle, /When no PR exists, run gt --no-interactive submit --no-edit \(without --update-only\)/);
  assert.match(cycle, /If verification fails, return submitted=false and do not link Linear/);
});
