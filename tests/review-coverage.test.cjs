// No Grok agents/tools are launched. Execute actual, extracted pure Rhai guards
// after translating their deliberately small common JS/Rhai syntax subset.
// This is not a full Rhai interpreter or a substitute for host compilation.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '..');
const branch = fs.readFileSync(path.join(root, 'branch-review.rhai'), 'utf8');
const gate = fs.readFileSync(path.join(root, 'preflight-gate.rhai'), 'utf8');
function extract(source, name) {
  const start = source.indexOf(`fn ${name}(`);
  assert.notEqual(start, -1, name);
  let depth = 0, quoted = false, escape = false;
  for (let i = source.indexOf('{', start); i < source.length; i++) {
    const c = source[i];
    if (quoted) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === '"') quoted = false; continue; }
    if (c === '"') { quoted = true; continue; }
    if (c === '{') depth++;
    if (c === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw Error('Unclosed function');
}
function compile(source, names) {
  const context = vm.createContext({
    type_of: x => x == null ? '()' : Array.isArray(x) ? 'array' : typeof x === 'boolean' ? 'bool' : typeof x === 'object' ? 'map' : typeof x,
    trimmed: s => typeof s === 'string' ? s.trim() : '',
    as_array: a => Array.isArray(a) ? a : [],
    json_encode: JSON.stringify,
  });
  for (const name of names) {
    const rhai = extract(source, name);
    assert(!/\b(for|while|try|catch)\b/.test(rhai), 'guard translator supports straight-line conditionals only');
    let js = rhai.replace(/^fn /, 'function ').replace(/== \(\)/g, '== null').replace(/!= \(\)/g, '!= null')
      .replace(/\.len\(\)/g, '.length').replace(/#\{/g, '{').replace(/\bif ([^\n{]+) \{/g, 'if ($1) {');
    vm.runInContext(js, context);
  }
  return context;
}
const guard = compile(gate, ['verdict_complete', 'gate_blocked', 'lane_from', 'evidence_complete']);
const bguard = compile(branch, ['review_complete', 'verdict_complete']);
const verdict = (real, extra = {}) => ({success: true, output: {coverage_complete: true, real, reason: 'Inspected code', evidence: 'actual source', ...extra}});
const lane = (findings = []) => ({success: true, output: {coverage_complete: true, findings, summary: 'Inspected all changes'}});

test('actual verdict guard separates evidence-backed rejection from failed/unresolved verification', () => {
  for (const g of [guard, bguard]) {
    assert.equal(g.verdict_complete(verdict(false)), true);
    assert.equal(g.verdict_complete(verdict(true)), true);
    for (const input of [null, {}, {success:false}, {success:true}, verdict(false, {coverage_complete:false}), verdict(false, {evidence:''}), verdict(false, {reason:' '}), verdict('false'), {success:true, output:{real:false}}]) {
      assert.equal(g.verdict_complete(input), false, JSON.stringify(input));
    }
  }
});
test('actual scan and review guards refuse missing/malformed/truncated coverage', () => {
  assert.equal(guard.lane_from(lane()).ok, true);
  assert.equal(bguard.review_complete(lane()), true);
  for (const input of [null, {}, {success:false}, {success:true}, {success:true,output:{}}, lane('not an array'), {success:true,output:{findings:[]}}, {success:true,output:{findings:[],coverage_complete:false}}]) {
    assert.equal(guard.lane_from(input).ok, false);
    assert.equal(bguard.review_complete(input), false);
  }
});
test('actual gate guard fails closed for each coverage gap, even without confirmed defects', () => {
  assert.equal(guard.gate_blocked(0,0,0,false), false);
  for (const args of [[1,0,0,false],[0,1,0,false],[0,0,1,false],[0,0,0,true],[0,0,12,false]]) assert.equal(guard.gate_blocked(...args), true);
});
// Execute the real scheduler snippet with a mock budget host. This protects
// omitted candidates at both the MAX_VERIFY cap and exhausted budget.
function schedule(count, remaining) {
  const start = gate.indexOf('let to_verify = take_n(blockers, MAX_VERIFY);');
  const end = gate.indexOf('let confirmed = [];', start);
  assert(start > 0 && end > start);
  const snippet = gate.slice(start,end).replace(/\.len\(\)/g,'.length').replace(/\bif ([^\n{]+) \{/g,'if ($1) {');
  const context = vm.createContext({blockers: Array.from({length:count},(_,i)=>({id:i})), MAX_VERIFY:12, budget:()=>({remaining}), take_n:(xs,n)=>xs.slice(0,n)});
  return vm.runInContext(snippet + '\n({to_verify, unresolved})',context);
}
test('actual scheduler preserves unresolved candidates beyond caps and budget', () => {
  for (const [count,budget,expected] of [[0,0,0],[5,0,5],[5,-1,5],[5,2,3],[20,100,8],[20,4,16],[5,100,0]]) {
    const result = schedule(count,budget);
    assert.equal(result.unresolved,expected);
    assert.equal(result.to_verify.length+result.unresolved,count);
    assert.equal(guard.gate_blocked(0,0,result.unresolved,false),expected > 0);
  }
});
test('all scan slots and verifier slots are visited, including missing results', () => {
  assert.match(gate,/while li < 3/);
  assert.match(gate,/scanned\.len\(\) != 3/);
  assert.match(gate,/while i < to_verify\.len\(\)/);
  assert.match(gate,/if !verdict_complete\(v\) \{\s*unresolved \+= 1;/);
  assert.match(gate,/gate_blocked\(failed_lanes\.len\(\), confirmed\.len\(\), unresolved, coverage_incomplete\)/);
  assert.match(branch,/results\.len\(\) != files\.len\(\)/);
  assert.match(branch,/verdicts\.len\(\) != findings\.len\(\)/);
});
test('exact root and triple-dot scope are collected; bounded full evidence feeds shellless reviewers', () => {
  for (const source of [branch,gate]) {
    assert.doesNotMatch(source,/\b(?:let raw|diff) = git_diff_since\(/);
    assert.match(source,/label: "scope", capability_mode: "execute"/);
    assert.doesNotMatch(source,/agent_type: "explore"/);
    assert.equal((source.match(/capability_mode: "execute"/g)||[]).length,1);
    assert.match(source,/You have no shell/);
    assert.match(source,/MAX_EVIDENCE_CHARS/);
    assert.doesNotMatch(source,/diff = excerpt|map\[current\] = clip/);
  }
  assert.match(branch,/json_encode\(#\{root: root, base: base, head: head\}\)/);
  assert.match(branch,/git merge-base BASE_COMMIT HEAD_COMMIT/);
  assert.match(branch,/scope\.merge_base \+ "\.\." \+ scope\.head_commit/);
  assert.match(branch,/source_at_head: scope\.sources\[path\]/);
  assert.match(branch,/source_at_head: scope\.sources\[f.file\]/);
  assert.match(gate,/ls-files --others --exclude-standard -z/);
});

test('git collector command contract honors nested checkout, slash ref, merge base, and non-HEAD target', () => {
  const {execFileSync} = require('node:child_process');
  const os = require('node:os');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'review-coverage-'));
  const checkout = path.join(dir,'nested checkout');
  fs.mkdirSync(checkout);
  const git = (...args) => execFileSync('git',['-C',checkout,...args],{encoding:'utf8'}).trim();
  const commit = (file,content) => { fs.writeFileSync(path.join(checkout,file),content); git('add','--',file); git('commit','-qm',file); return git('rev-parse','HEAD'); };
  try {
    git('init','-q'); git('config','user.email','test@example.invalid'); git('config','user.name','Coverage Fixture');
    const common = commit('common.txt','shared\n');
    git('checkout','-qb','main'); commit('main-only.txt','base advanced\n');
    git('update-ref','refs/remotes/origin/main',git('rev-parse','HEAD'));
    git('checkout','-qb','review-target',common); const target = commit('feature.txt','requested change\n');
    commit('head-only.txt','not requested\n'); fs.writeFileSync(path.join(checkout,'dirty.txt'),'not requested\n');
    const base = git('rev-parse','--verify','--end-of-options','origin/main^{commit}');
    const head = git('rev-parse','--verify','--end-of-options',target+'^{commit}');
    const merge = git('merge-base',base,head);
    assert.equal(merge,common);
    const files = git('diff','--name-only','-z','--no-renames',merge,head,'--').split('\0').filter(Boolean);
    assert.deepEqual(files,['feature.txt']);
    assert.equal(git('show',head+':feature.txt'),'requested change');
    const diff = git('diff','--no-ext-diff','--no-textconv','--no-renames',merge,head,'--');
    assert.match(diff,/requested change/);
    assert.doesNotMatch(diff,/head-only|main-only|dirty/);
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});

test('actual per-file diff extractor preserves findings beyond the former 8000-character cut', () => {
  const rhai = extract(branch,'extract_selected_diffs');
  const js = rhai.replace(/^fn /,'function ').replace(/#\{/g,'{')
    .replace(/for (\w+) in (\w+) \{/g,'for (const $1 of $2) {')
    .replace(/\bif ([^\n{]+) \{/g,'if ($1) {');
  const ctx = vm.createContext({type_of:x=>typeof x, trimmed:s=>s.trim(), starts_with:(s,p)=>s.startsWith(p), b_path_from_git_line:s=>s.split(' b/')[1]||''});
  vm.runInContext(js,ctx);
  const large = 'diff --git a/large.txt b/large.txt\n' + '+safe\n'.repeat(2000) + '+TAIL_DEFECT';
  const next = 'diff --git a/next.txt b/next.txt\n+next';
  const result = ctx.extract_selected_diffs(large+'\n'+next,{'large.txt':true,'next.txt':true});
  assert.equal(result['large.txt'],large);
  assert.equal(result['next.txt'],next);
  assert.match(result['large.txt'],/TAIL_DEFECT$/);
});

test('actual evidence guard requires bounded staged and unstaged snapshots', () => {
  const complete = {diff:'',staged_diff:'+staged',unstaged_diff:'-staged',staged_sources:{'config.txt':'staged'},status:'MM config.txt',untracked:[]};
  assert.equal(guard.evidence_complete(complete,120000),true);
  for (const key of ['diff','staged_diff','unstaged_diff','staged_sources','status','untracked']) {
    const missing = {...complete}; delete missing[key];
    assert.equal(guard.evidence_complete(missing,120000),false,key);
  }
  assert.equal(guard.evidence_complete({...complete,staged_sources:{'config.txt':'x'.repeat(120001)}},120000),false);
  assert.equal(guard.evidence_complete({...complete,staged_diff:'x'.repeat(120001)},120000),false);
});

test('git collector retains staged unsafe change canceled by an unstaged reversion', () => {
  const {execFileSync} = require('node:child_process');
  const os = require('node:os');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'review-coverage-index-'));
  const git = (...args) => execFileSync('git',['-C',dir,...args],{encoding:'utf8'}).trim();
  const file = path.join(dir,'auth.txt');
  try {
    git('init','-q'); git('config','user.email','test@example.invalid'); git('config','user.name','Coverage Fixture');
    fs.writeFileSync(file,'require_auth=true\n'); git('add','--','auth.txt'); git('commit','-qm','baseline');
    fs.writeFileSync(file,'require_auth=false\n'); git('add','--','auth.txt');
    fs.writeFileSync(file,'require_auth=true\n'); // Restore worktree only; dangerous index remains.
    const combined = git('diff','--no-ext-diff','--no-textconv','--no-renames','HEAD','--');
    const staged = git('diff','--no-ext-diff','--no-textconv','--no-renames','--cached','HEAD','--');
    const unstaged = git('diff','--no-ext-diff','--no-textconv','--no-renames','--');
    const indexSource = git('show',':auth.txt');
    assert.equal(combined,'');
    assert.match(staged,/\+require_auth=false/);
    assert.match(unstaged,/-require_auth=false/);
    assert.equal(indexSource,'require_auth=false');
    assert.equal(fs.readFileSync(file,'utf8'),'require_auth=true\n');
    assert.equal(guard.evidence_complete({diff:combined,staged_diff:staged,unstaged_diff:unstaged,staged_sources:{'auth.txt':indexSource},status:git('status','--porcelain'),untracked:[]},120000),true);
    assert.equal((gate.match(/staged_diff: scope.staged_diff, unstaged_diff: scope.unstaged_diff, staged_sources: scope.staged_sources/g)||[]).length,2,'both scanner and verifier receive index evidence');
    assert.match(gate,/A staged defect remains a blocker even if an unstaged edit removes it/);
    assert.doesNotMatch(gate,/confirmed a clean tree with git status\/diff/);
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});
