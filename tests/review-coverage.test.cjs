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
    starts_with: (s,p) => s.startsWith(p),
    ends_with: (s,p) => s.endsWith(p),
    contains: (s,p) => s.includes(p),
  });
  for (const name of names) {
    const rhai = extract(source, name);
    assert(!/\b(while|try|catch)\b/.test(rhai), 'guard translator supports conditionals and simple array iteration only');
    let js = rhai.replace(/^fn /, 'function ').replace(/== \(\)/g, '== null').replace(/!= \(\)/g, '!= null')
      .replace(/for (\w+) in (\w+) \{/g, 'for (const $1 of $2) {').replace(/\.len\(\)/g, '.length').replace(/#\{/g, '{').replace(/\bif ([^\n{]+) \{/g, 'if ($1) {');
    vm.runInContext(js, context);
  }
  return context;
}
const guard = compile(gate, ['verdict_complete', 'gate_blocked', 'lane_from', 'evidence_complete', 'is_block_severity']);
const bguard = compile(branch, ['review_complete', 'verdict_complete', 'same_file_set', 'skip_file']);
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
    assert.equal((source.match(/capability_mode: "execute"/g)||[]).length,source === branch ? 2 : 1);
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

test('actual branch manifest guard requires bidirectional agreement with diff paths', () => {
  assert.equal(bguard.same_file_set(['a.txt','b.txt'],['b.txt','a.txt']),true);
  assert.equal(bguard.same_file_set([],[]),true);
  for (const [manifest,diffPaths] of [
    [['a.txt'],['a.txt','b.txt']], // Collector omitted a changed file.
    [['a.txt','b.txt'],['a.txt']], // Collector claims a file without diff evidence.
    [[],['a.txt']], [['a.txt'],[]],
    [['a.txt','a.txt'],['a.txt','b.txt']],
    [['a.txt','b.txt'],['a.txt','a.txt']],
    [[''],['']], [[123],[123]], [null,[]],
  ]) assert.equal(bguard.same_file_set(manifest,diffPaths),false,JSON.stringify([manifest,diffPaths]));
  assert.match(branch,/if !same_file_set\(parsed, parse_diff_files\(diff\)\) \{\s*pause\("verification"/);
});

test('actual preflight baseline assignment pins subsequent reports and verification', () => {
  const assignment = gate.match(/root = scope.root;\s*since_ref = scope.baseline;\s*let encoded_since = json_encode\(since_ref\);/);
  assert(assignment,'resolved baseline must replace caller ref');
  const ctx = vm.createContext({root:'.', since_ref:'moving-branch',scope:{root:'/nested/repo',baseline:'a'.repeat(40)},json_encode:JSON.stringify});
  const result = vm.runInContext(assignment[0]+'\n({since_ref,encoded_since})',ctx);
  assert.equal(result.since_ref,'a'.repeat(40));
  assert.equal(result.encoded_since,JSON.stringify('a'.repeat(40)));
  assert.match(gate,/md \+= since_ref;/);
  assert.match(gate,/since: since_ref,/);
});

test('actual lane routing verifies unknown severity as a blocker with an explicit reason', () => {
  const start = gate.indexOf('        for f in kept {');
  const end = gate.indexOf('        log("Lane "',start);
  assert(start > 0 && end > start);
  const js = gate.slice(start,end).replace(/for (\w+) in (\w+) \{/g,'for (const $1 of $2) {')
    .replace(/#\{/g,'{').replace(/\bif ([^\n{]+) \{/g,'if ($1) {');
  const kept = ['block','warn','critical','',null].map(severity=>({file:'a.txt',issue:'issue',evidence:'quote',severity}));
  const ctx = vm.createContext({kept,name:'diff',coverage_incomplete:false,blockers:[],warnings:[],trimmed:x=>typeof x==='string'?x.trim():'',json_encode:JSON.stringify,log:()=>{},is_block_severity:guard.is_block_severity});
  const result = vm.runInContext(js+'\n({blockers,warnings,coverage_incomplete})',ctx);
  assert.equal(result.blockers.length,4);
  assert.equal(result.warnings.length,1);
  assert.equal(result.warnings[0].severity,'warn');
  assert.equal(result.coverage_incomplete,true);
  for (const item of result.blockers.slice(1)) {
    assert.equal(item.severity,'block');
    assert.match(item.severity_reason,/Unknown scanner severity.*candidate blocker pending verification/);
  }
});

function selectBranchFiles(parsed, explicit = []) {
  const start = branch.indexOf('let files = [];\nlet skipped_n = 0;');
  const end = branch.indexOf('\nif files.len() == 0 {',start);
  assert(start > 0 && end > start);
  const js = branch.slice(start,end).replace(/for (\w+) in (\w+) \{/g,'for (const $1 of $2) {')
    .replace(/#\{/g,'{').replace(/\.len\(\)/g,'.length').replace(/\.to_string\(\)/g,'.toString()')
    .replace(/\bif ([^\n{]+) \{/g,'if ($1) {');
  const ctx = vm.createContext({parsed,explicit,skip_file:bguard.skip_file,log:()=>{},pause:()=>{throw Error('incomplete');}});
  return vm.runInContext(js+'\n({files,skipped_n})',ctx);
}

test('actual selection runs before source collection and honors explicitly requested skipped files', () => {
  assert.deepEqual(Array.from(selectBranchFiles(['asset.png','app.js']).files),['app.js']);
  assert.deepEqual(Array.from(selectBranchFiles(['asset.png','app.js'],['asset.png']).files),['asset.png']);
  assert.throws(()=>selectBranchFiles(['app.js'],['absent.js']),/incomplete/);
  const selection = branch.indexOf('if skip_file(p)');
  const sourceCollection = branch.indexOf('let source_result = agent(source_prompt');
  assert(selection > 0 && sourceCollection > selection);
  assert.match(branch,/head_commit: scope.head_commit, files: files, max_source_chars:/);
  assert.match(branch,/Never collect blobs for unselected files/);
  assert.match(branch,/explicitly selected binary files must fail incomplete/);
});

test('real binary-plus-source fixture preserves full manifest without collecting excluded binary blobs', () => {
  const {execFileSync} = require('node:child_process');
  const os = require('node:os');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'review-coverage-binary-'));
  const git = (...args) => execFileSync('git',['-C',dir,...args],{encoding:'utf8'}).trim();
  try {
    git('init','-q'); git('config','user.email','test@example.invalid'); git('config','user.name','Coverage Fixture');
    fs.writeFileSync(path.join(dir,'app.js'),'export const n = 1;\n'); git('add','.'); git('commit','-qm','base');
    const base = git('rev-parse','HEAD');
    fs.writeFileSync(path.join(dir,'asset.png'),Buffer.alloc(150000,0));
    fs.writeFileSync(path.join(dir,'app.js'),'export const n = 2;\n'); git('add','.'); git('commit','-qm','mixed change');
    const head = git('rev-parse','HEAD');
    const manifest = git('diff','--name-only','-z','--no-renames',base,head,'--').split('\0').filter(Boolean);
    const diff = git('diff','--no-ext-diff','--no-textconv','--no-renames',base,head,'--');
    const headers = [...diff.matchAll(/^diff --git a\/.* b\/(.*)$/gm)].map(m=>m[1]);
    assert.equal(bguard.same_file_set(manifest,headers),true);
    assert.match(diff,/Binary files/);
    const selected = selectBranchFiles(manifest);
    assert.deepEqual(Array.from(selected.files),['app.js']);
    const sources = Object.fromEntries(Array.from(selected.files,p=>[p,git('show',head+':'+p)]));
    assert.equal(sources['asset.png'],undefined);
    assert.equal(sources['app.js'],'export const n = 2;');
    assert(diff.length+JSON.stringify(sources).length < 120000);
    assert.equal(selected.skipped_n,1);
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});
test('ordinary Unicode paths match verbatim manifests with core.quotePath=false', () => {
  const {execFileSync} = require('node:child_process');
  const os = require('node:os');
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'review-coverage-unicode-'));
  const git=(...args)=>execFileSync('git',['-C',dir,...args],{encoding:'utf8'}).trim();
  try {
    git('init','-q');git('config','user.email','test@example.invalid');git('config','user.name','Coverage Fixture');
    fs.writeFileSync(path.join(dir,'café.txt'),'before\n');git('add','.');git('commit','-qm','base');
    const base=git('rev-parse','HEAD');
    fs.writeFileSync(path.join(dir,'café.txt'),'after\n');git('add','.');git('commit','-qm','change');
    const head=git('rev-parse','HEAD');
    const manifest=git('diff','--name-only','-z',base,head,'--').split('\0').filter(Boolean);
    const quoted=git('-c','core.quotePath=true','diff',base,head,'--');
    assert.match(quoted,/\\303\\251/);
    const diff=git('-c','core.quotePath=false','diff','--no-ext-diff','--no-textconv','--no-renames',base,head,'--');
    const headers=[...diff.matchAll(/^diff --git a\/.* b\/(.*)$/gm)].map(m=>m[1]);
    assert.equal(bguard.same_file_set(manifest,headers),true);
    assert.deepEqual(headers,['café.txt']);
    assert.match(branch,/git -c core.quotePath=false diff --no-ext-diff/);
  } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
