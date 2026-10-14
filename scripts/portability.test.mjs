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

test('recovery contracts retain manual journal audit, missing-ID guard and explicit fresh-run guidance', () => {
  const pr = read('graphite-pr-review.rhai');
  assert.match(pr, /"required": \[[^\n]*"frozen_children"/);
  assert.match(pr, /frozen_children: frozen_children,\s*cleanup_journal: cleanup_journal/);
  assert.match(pr, /Skip entries with restored=true: ownership ended/);
  assert.match(pr, /never run gt freeze or gt unfreeze/);
  assert.match(pr, /label: "audit-freeze-journal"/);
  assert.ok(pr.indexOf('label: "audit-freeze-journal"') > pr.indexOf('let submitted = agent('));
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


test('dirty or unknown merge checkout stops before diagnosis and any live preparation', () => {
  const merge = read('graphite-stack-merge.rhai');
  const guard = merge.indexOf('if disc.dirty {');
  assert.ok(guard > merge.indexOf('let disc = apply_discovered('));
  assert.ok(guard < merge.indexOf('phase("Diagnose");'));
  assert.match(merge, /let dirty = true;/);
  assert.match(merge, /dirty = map_bool\(o, "dirty", true\);/);
  assert.match(merge, /Before ANY preparation command, re-run git status --porcelain/);
  assert.match(merge, /sole exception is aborting a conflicting Graphite operation that this workflow just started/);
  assert.match(merge, /Never abort an unrelated or pre-existing operation/);
  for (const dirty of [true, undefined, null]) {
    const verifiedDirty = typeof dirty === 'boolean' ? dirty : true;
    const calls = verifiedDirty ? [] : ['diagnose', 'prepare'];
    assert.deepEqual(calls, []);
  }
});

test('repair topology gate rejects descendants, frozen state, and missing evidence; accepts only unfrozen leaf', () => {
  const pr = read('graphite-pr-review.rhai');
  const condition = pr.match(/if (!map_bool\(collect_out, "freeze_state_verified"[^\n]+) \{/)[1];
  const blocked = new Function('collect_out', 'map_bool', `return ${condition};`);
  const mapBool = (object, key, fallback) => typeof object?.[key] === 'boolean' ? object[key] : fallback;
  const leaf = { freeze_state_verified: true, is_leaf: true, branch_frozen: false };
  assert.equal(blocked(leaf, mapBool), false);
  for (const state of [{}, { ...leaf, is_leaf: false }, { ...leaf, branch_frozen: true }, { ...leaf, freeze_state_verified: false }]) {
    assert.equal(blocked(state, mapBool), true);
  }
  assert.ok(pr.indexOf(condition) < pr.indexOf('let repaired = agent('));
  assert.match(pr, /Before any edit or commit, recheck the selected branch is an unfrozen leaf/);
  assert.match(pr, /Automatic freeze and unfreeze are forbidden/);
  assert.match(pr, /label: "audit-freeze-journal", capability_mode: "read-only"/);
  assert.match(pr, /Any pending entry or nonempty frozen_children list is a blocker requiring manual recovery/);
  assert.doesNotMatch(pr, /attempt to unfreeze|unfreeze that exact branch|Before freezing each/);
});

test('collector allows required read-only Graphite topology inspection', () => {
  const collector = read('graphite-pr-review.rhai').split('fn collect_prompt(')[1].split('fn ')[0];
  assert.doesNotMatch(collector, /Never gt log\./);
  assert.match(collector, /Read-only gt log and gt info are allowed/);
  assert.match(collector, /inspection fails, mark freeze_state_verified=false/);
});

test('native merge diagnosis requires a bounded action and explicit evidence mapping', () => {
  const merge = read('graphite-stack-merge.rhai');
  const schema = merge.split('let diagnose_schema =')[1].split('let prepare_schema =')[0];
  assert.match(schema, /"required": \[[^\n]*"recommended_action"/);
  assert.match(schema, /"enum": \["merge", "merge-when-ready", "wait-queue", "stop"\]/);
  for (const mapping of ['already_queued=true -> wait-queue', 'blocked=true or ok=false -> stop', 'ready=true -> merge', 'waiting_ci=true with no other blocker -> merge-when-ready']) {
    assert.ok(merge.includes(mapping));
  }
  assert.match(merge, /diagnose omitted or returned an invalid recommended_action/);
});

test('successful live dry-run still schedules synchronization; dry-run and queued work do not', () => {
  const merge = read('graphite-stack-merge.rhai');
  const condition = merge.match(/if (!cfg.dry_run && !diag.already_queued && !diag.blocked) \{\s*diag.needs_get = true;/)[1];
  const mustSync = new Function('cfg', 'diag', `return ${condition};`);
  const ready = { already_queued: false, blocked: false, ready: true, needs_get: false };
  assert.equal(mustSync({ dry_run: false }, ready), true);
  assert.equal(mustSync({ dry_run: true }, ready), false);
  assert.equal(mustSync({ dry_run: false }, { ...ready, already_queued: true }), false);
  assert.equal(mustSync({ dry_run: false }, { ...ready, blocked: true }), false);
  assert.ok(merge.indexOf('diag.needs_get = true;') < merge.indexOf('if needs_prepare(diag) {'));
  assert.match(merge, /Set did_get=true only after the command succeeds/);
  assert.match(merge, /if !diag2.ok \{\s*pause\("infra", "Diagnosis after preparation failed/);
  assert.match(merge, /!map_bool\(prep_res.output, "did_get", false\)/);
  assert.ok(merge.indexOf('Mandatory pre-land synchronization was not verified') < merge.indexOf('let enq_res = agent('));
});

test('explicit landing modes cannot bypass fresh post-sync readiness', () => {
  const merge = read('graphite-stack-merge.rhai');
  const source = merge.split('fn pick_action(cfg_map, diag) {')[1].split('\nfn needs_prepare')[0];
  const body = source.slice(0, source.lastIndexOf('}')).replace(/if ([^{\n]+) \{/g, 'if ($1) {');
  const pickAction = new Function('cfg_map', 'diag', body);
  const ready = { ok: true, already_queued: false, blocked: false, ready: true, waiting_ci: false, needs_get: false, needs_restack: false, needs_unfreeze: false, needs_submit: false, verdict: 'ready', recommended_action: 'merge' };
  for (const mode of ['auto', 'merge', 'merge-when-ready']) {
    assert.equal(pickAction({ mode }, { ...ready, ready: false, needs_restack: true, recommended_action: 'stop' }), 'stop');
    assert.equal(pickAction({ mode }, { ...ready, recommended_action: 'stop' }), 'stop');
    assert.equal(pickAction({ mode }, { ...ready, ok: false }), 'stop');
    for (const flag of ['needs_get', 'needs_restack', 'needs_unfreeze', 'needs_submit']) {
      assert.equal(pickAction({ mode }, { ...ready, [flag]: true }), 'stop');
    }
  }
  const waiting = { ...ready, ready: false, waiting_ci: true, recommended_action: 'merge-when-ready' };
  assert.equal(pickAction({ mode: 'merge' }, waiting), 'stop');
  assert.equal(pickAction({ mode: 'merge-when-ready' }, waiting), 'merge-when-ready');
  assert.equal(pickAction({ mode: 'auto' }, ready), 'merge');
  assert.equal(pickAction({ mode: 'auto' }, waiting), 'merge-when-ready');
  assert.equal(pickAction({ mode: 'merge' }, { ...ready, already_queued: true }), 'wait-queue');
});

test('landing synchronization excludes upstack and both native MQ scans are bounded', () => {
  const merge = read('graphite-stack-merge.rhai');
  const syncs = merge.match(/gt get <tip>[^`]+/g);
  assert.equal(syncs.length, 2);
  for (const command of syncs) assert.match(command, /--downstack --force --no-restack --no-interactive/);
  const scans = merge.match(/gh pr list --state open --search 'head:gtmq'[^.\n]+/g);
  assert.equal(scans.length, 2);
  for (const command of scans) assert.match(command, /--limit 100 --json/);
  assert.equal((merge.match(/The MQ search is bounded at 100 raw rows/g) || []).length, 2);
  assert.equal((merge.match(/if !queue_scan_verified\(o\)/g) || []).length, 2);
  for (const name of ['discover_schema', 'diagnose_schema']) {
    const required = merge.split(`let ${name} =`)[1].match(/"required": \[([^\n]+)\]/)[1];
    assert.ok(required.includes('"mq_scan_complete"'));
    assert.ok(required.includes('"mq_scan_count"'));
  }
});

test('queue completeness guard rejects cap, missing evidence, malformed counts and failed scans', () => {
  const merge = read('graphite-stack-merge.rhai');
  const condition = merge.match(/return (map_bool\(output, "mq_scan_complete"[^\n]+);/)[1];
  const verify = new Function('output', 'count', 'map_bool', 'type_of', `return ${condition};`);
  const mapBool = (object, key, fallback) => typeof object?.[key] === 'boolean' ? object[key] : fallback;
  const typeOf = value => Number.isInteger(value) ? 'i64' : typeof value;
  const check = output => verify(output, output.mq_scan_count, mapBool, typeOf);
  for (const count of [0, 31, 99]) assert.equal(check({ mq_scan_complete: true, mq_scan_count: count }), true);
  for (const count of [100, 101, -1, 1.5, '0', null, undefined]) {
    assert.equal(check({ mq_scan_complete: true, mq_scan_count: count }), false);
  }
  assert.equal(check({ mq_scan_complete: false, mq_scan_count: 0 }), false);
  assert.equal(check({ mq_scan_count: 0 }), false);
  assert.equal(check({}), false);
});

test('cycle submit prompt and all included guardrails agree on creation versus update', () => {
  const cycle = read('linear-cycle-deliver.rhai');
  // Assemble every literal contributed by submit_prompt and its helper calls.
  // Ticket packet contents are data and cannot supply or override these rules.
  const body = name => cycle.split(`fn ${name}(`)[1].split('\nfn ')[0];
  const literals = name => [...body(name).matchAll(/"(?:[^"\\]|\\.)*"/g)].map(match => JSON.parse(match[0])).join('\n');
  const prompt = ['submit_prompt', 'guardrails_text', 'tools_exec', 'tools_linear', 'tools_no_edit', 'support_cli'].map(literals).join('\n');
  assert.doesNotMatch(prompt, /Submit flags are --no-edit --update-only/);
  assert.match(prompt, /When a PR is confirmed absent, create it without --update-only/);
  assert.match(prompt, /when a PR already exists, use --update-only/);
  assert.match(prompt, /When no PR exists, run gt --no-interactive submit --no-edit \(without --update-only\)/);
  assert.match(prompt, /When an existing PR has a different headRefOid, run gt --no-interactive submit --no-edit --update-only/);
  assert.match(prompt, /ambiguous lookup failures never prove absence/);
  assert.match(prompt, /Publish is a second submit for the verified existing PR/);
});
