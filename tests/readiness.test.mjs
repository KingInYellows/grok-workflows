import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import assert from 'node:assert/strict';

const source = name => readFileSync(fileURLToPath(new URL(`../${name}.rhai`, import.meta.url)), 'utf8');
const graphite = source('graphite-pr-review');
const multi = source('multi-track-ship');
// These deliberately tiny predicates use syntax shared by Rhai and JavaScript.
// Execute the actual source expression, not a duplicate implementation. This
// does NOT replace Rhai parsing or live host integration testing.
function predicate(text, name) {
  const m = text.match(new RegExp(`fn ${name}\\(([^)]*)\\) \\{\\s*return ([^;]+);\\s*\\}`));
  assert.ok(m, `${name} must remain a pure explicit-return predicate`);
  assert.match(m[2], /^[a-z0-9_ ()&|=!<>]+$/i, 'only boolean expression syntax supported');
  return Function(...m[1].split(',').map(x => x.trim()), `return ${m[2]};`);
}
const canSubmit = predicate(graphite, 'repair_can_submit');
const canPass = predicate(multi, 'pipeline_can_pass');

test('submission requires successful, tested, clean, identified repair for all 64 combinations', () => {
  for (let bits=0; bits<64; bits++) {
    const flags = Array.from({length:6}, (_,i) => Boolean(bits & (1<<i)));
    const [ok, committed, present, clean, tests, sha] = flags;
    let submitted=0;
    if (canSubmit(...flags)) submitted++; // mocked submit host
    assert.equal(submitted, Number(ok && clean && tests && sha && (committed || present)), flags.join(','));
  }
});
test('real submit callsite is guarded by the tested repair result and coverage', () => {
  assert.match(graphite, /if repair_can_submit\(map_bool\(repair_out, "ok", false\), repair_committed, already_present, tree_clean, tests_passed, repair_sha != ""\) \{\s*repair_ready = true;/);
  assert.match(graphite, /if do_submit && repair_ready && coverage_complete \{/);
  assert.doesNotMatch(graphite, /if repair_committed \|\|/);
});
test('pipeline success needs this attempt success, pass and nonempty evidence', () => {
  for (let bits=0; bits<8; bits++) {
    const flags = Array.from({length:3}, (_,i) => Boolean(bits & (1<<i)));
    assert.equal(canPass(...flags), bits === 7);
  }
  assert.match(multi, /last_pipe_evidence = "";\s*let pr = run_pipeline\("full-/);
});
test('visual repair invalidates old pipeline before writer, reruns full pipeline and blocks failed rerun', () => {
  const start = multi.indexOf('// Any writer invalidates');
  const end = multi.indexOf('// --- Gate', start);
  assert.ok(start > 0 && end > start);
  const block = multi.slice(start,end);
  assert.ok(block.indexOf('pipeline_passed = false;') < block.indexOf('let vfr = agent('));
  assert.ok(block.indexOf('let post_vp = run_pipeline(') > block.indexOf('let vfr = agent('));
  assert.match(block, /"FULL pipeline after visual\/perf repair", true, pipeline_schema/);
  assert.match(block, /pipeline_passed = pipeline_can_pass\(post_vp.success == true, po.passed == true, trimmed\(last_pipe_evidence\) != ""\);/);
  assert.match(block, /if !pipeline_passed \{[\s\S]*?break;/);
  assert.match(multi, /if !pipeline_passed \|\| !visual_perf_passed \{\s*is_complete = false;/);
  // A prior green result cannot make a post-edit regression eligible.
  let pipeline = canPass(true,true,true);
  pipeline = false; // required before the writer above
  pipeline = canPass(true,false,true); // post-edit unit test regression
  const visual = true;
  assert.equal(pipeline && visual, false);
});
test('truncated or absent evidence visibly marks partial coverage and blocks submit', () => {
  assert.match(graphite, /if map_bool\(collect_out, "diff_truncated", false\) \|\| raw_diff.len\(\) > MAX_DIFF_CHARS \{\s*coverage_complete = false;/);
  assert.match(graphite, /if review_diff == "" && changed_files.len\(\) > 0 \{\s*coverage_complete = false;/);
  assert.match(graphite, /Review coverage complete:/);
  assert.match(graphite, /This is a partial review, not a merge-readiness verdict\. Submit is blocked\./);
});
test('upstream and local coverage caps fail closed instead of becoming clean review', () => {
  assert.match(graphite, /for flag in \["diff_truncated", "agents_truncated", "threads_truncated", "files_truncated"\] \{\s*if map_bool\(collect_out, flag, true\) \{\s*coverage_complete = false;/);
  assert.match(graphite, /if threads.len\(\) >= MAX_THREADS \{\s*coverage_complete = false;/);
  assert.match(graphite, /if map_str\(row, "body"\).len\(\) > 500 \{\s*coverage_complete = false;/);
  assert.match(graphite, /if kept_here >= MAX_FINDINGS_PER_REVIEW \|\| findings.len\(\) >= MAX_FINDINGS \{\s*coverage_complete = false;/);
  assert.match(graphite, /if !map_bool\(out, "coverage_complete", false\) \{\s*coverage_complete = false;/);
});
test('every triage slot requires a resolved evidence-backed verdict, including refutations', () => {
  const ready = predicate(graphite, 'triage_is_complete');
  for (let bits=0; bits<32; bits++) {
    const flags=Array.from({length:5}, (_,i) => Boolean(bits & (1<<i)));
    assert.equal(ready(...flags), bits === 31);
  }
  assert.match(graphite, /if !triage_is_complete\(out != \(\), map_bool\(out, "coverage_complete", false\), map_str\(out, "reason"\) != "", map_str\(out, "evidence"\) != "", valid_verdict\) \{\s*coverage_complete = false;/);
  assert.match(graphite, /valid_verdict = type_of\(map_get\(out, "real"\)\) == "bool";/);
  assert.match(graphite, /valid_verdict = list_has\(\["actionable_valid", "already_fixed", "duplicate", "informational", "false_positive", "human_blocker"\], map_str\(out, "class"\)\);/);
});
test('skipped tests and incomplete plan verdicts cannot authorize submission', () => {
  const tested = predicate(graphite, 'tests_were_verified');
  for (const passed of [false,true]) for (const count of [0,1,2]) for (const evidence of [false,true]) {
    assert.equal(tested(passed,count,evidence), passed && count > 0 && evidence);
  }
  const planned = predicate(graphite, 'plan_verdict_complete');
  for (const matches of [0,1,2]) for (const valid of [false,true]) assert.equal(planned(matches,valid), matches === 1 && valid);
  assert.match(graphite, /let tests_passed = tests_were_verified\(map_bool\(repair_out, "tests_passed", false\), map_int\(repair_out, "tests_executed"\), map_str\(repair_out, "test_evidence"\) != ""\);/);
  assert.doesNotMatch(graphite, /every command is none, set tests_passed=true/);
  assert.match(graphite, /if !plan_verdict_complete\(matched, verdict_valid\) \{\s*coverage_complete = false;/);
  assert.match(graphite, /if accepted && !rejected && matched == 1 && verdict_valid \{/);
});
test('repair cleanliness preserves the collector allowed-untracked-note policy', () => {
  assert.match(graphite, /Use the same normalized cleanliness rule as collection: ignore ONLY untracked paths under plans\/, \.grok\/, docs\/goals\/, docs\/brainstorms\/, and docs\/solutions\//);
  assert.match(graphite, /Any other modified, staged, deleted or untracked path means clean=false/);
  assert.match(graphite, /Never delete, stage or stash ignored notes/);
});

// Execute the actual bounded-loop Rhai helper with mock host-value adapters.
// This subset translation does not claim full Rhai compilation/integration.
function missingRepairSourcesFunction() {
  const start = graphite.indexOf('fn missing_repair_sources(');
  assert.ok(start > 0);
  let depth=0, end=-1;
  for (let i=graphite.indexOf('{',start); i<graphite.length; i++) {
    if (graphite[i] === '{') depth++;
    if (graphite[i] === '}' && --depth === 0) { end=i+1; break; }
  }
  assert.ok(end > start);
  const js = graphite.slice(start,end).replace(/^fn /,'function ')
    .replace(/for (\w+) in ([^\n{]+) \{/g,'for (const $1 of $2) {')
    .replace(/\bif ([^\n{]+) \{/g,'if ($1) {');
  return Function('as_array','map_get','trimmed','list_has',js+'; return missing_repair_sources;')(
    v=>Array.isArray(v)?v:[], (v,k)=>v?.[k], v=>typeof v==='string'?v.trim():'', (vs,v)=>vs.includes(v));
}
const missingRepairSources = missingRepairSourcesFunction();
test('final accepted repair union must cover every kept source, including planner omissions', () => {
  const repair = (...source_ids) => ({source_ids});
  assert.deepEqual(missingRepairSources(['a','b'],[repair('a')]),['b']);
  assert.deepEqual(missingRepairSources(['a','b'],[]),['a','b']);
  assert.deepEqual(missingRepairSources(['a','b'],[repair('a','b')]),[]);
  assert.deepEqual(missingRepairSources(['a','b'],[repair('b'),repair('a'),repair('a')]),[]);
  assert.deepEqual(missingRepairSources(['a','b'],[repair('a','unknown')]),['b']);
  // Removing an otherwise valid repair because of a count/file cap or plan
  // rejection cannot silently turn an unresolved confirmed source into success.
  const beforeCap=[repair('a'),repair('b'),repair('c')];
  assert.deepEqual(missingRepairSources(['a','b','c'],beforeCap.slice(0,2)),['c']);
  assert.deepEqual(missingRepairSources(['a','b','c'],beforeCap.filter((_,i)=>i!==1)),['b']);
  // Genuine evidence-backed triage false positives are excluded from kept_ids;
  // they need no repair and do not block a complete plan for actual defects.
  assert.deepEqual(missingRepairSources(['real'],[repair('real')]),[]);
  assert.deepEqual(missingRepairSources([],[]),[]);
});
test('coverage guard runs after caps and before either repair or submit side effects', () => {
  const capped=graphite.indexOf('repairs = capped;');
  const guard=graphite.indexOf('let uncovered_sources = missing_repair_sources(kept_ids, repairs);');
  const apply=graphite.indexOf('if do_apply && repairs.len() > 0 && coverage_complete');
  const submit=graphite.indexOf('if do_submit && repair_ready && coverage_complete');
  assert.ok(capped > 0 && guard > capped && apply > guard && submit > guard);
  assert.match(graphite,/if uncovered_sources.len\(\) > 0 \{\s*coverage_complete = false;/);
  assert.match(graphite,/Confirmed source has no accepted repair after planning\/caps:/);
  const fpStart=graphite.indexOf('} else if class_name == "false_positive"');
  const fpEnd=graphite.indexOf('} else if class_name == "human_blocker"',fpStart);
  assert.ok(fpStart > 0 && fpEnd > fpStart);
  assert.doesNotMatch(graphite.slice(fpStart,fpEnd),/kept_ids.push/);
});

function loadReviewFns(names) {
  const parts = [];
  for (const name of names) {
    const start = graphite.indexOf(`fn ${name}(`);
    assert.ok(start > 0, name);
    let depth = 0, end = -1, quoted = false, escape = false;
    for (let i = graphite.indexOf('{', start); i < graphite.length; i++) {
      const c = graphite[i];
      if (quoted) {
        if (escape) escape = false;
        else if (c === '\\') escape = true;
        else if (c === '"') quoted = false;
        continue;
      }
      if (c === '"') { quoted = true; continue; }
      if (c === '{') depth++;
      if (c === '}' && --depth === 0) { end = i + 1; break; }
    }
    assert.ok(end > start, name);
    parts.push(graphite.slice(start, end));
  }
  const js = parts.join('\n')
    .replace(/^fn /gm, 'function ')
    .replace(/\.len\(\)/g, '.length')
    .replace(/\.contains\(/g, '.includes(')
    .replace(/(\w+)\.sub_string\(/g, 'sub_string($1, ')
    .replace(/#\{/g, '{')
    .replace(/for (\w+) in ([^\n{]+) \{/g, 'for (const $1 of $2) {')
    .replace(/\bif ([^\n{]+) \{/g, 'if ($1) {')
    .replace(/\bwhile ([^\n{]+) \{/g, 'while ($1) {');
  const type_of = x => x == null ? '()' : Array.isArray(x) ? 'array' : typeof x === 'boolean' ? 'bool' : typeof x === 'object' ? 'map' : typeof x;
  const trimmed = s => typeof s === 'string' ? s.trim() : '';
  const sub_string = (s, start, len) => String(s).substring(start, start + len);
  const list_has = (items, value) => Array.isArray(items) && items.includes(value);
  const as_array = v => Array.isArray(v) ? v : [];
  const map_get = (m, key) => (m && typeof m === 'object' ? m[key] : undefined);
  return Function('type_of', 'trimmed', 'sub_string', 'list_has', 'as_array', 'map_get', `${js}\nreturn { ${names.join(', ')} };`)(type_of, trimmed, sub_string, list_has, as_array, map_get);
}

test('reviewed sha, whole hunks, duplicate collapse, and residuals are host-enforced', () => {
  assert.match(graphite, /Workflow version 1\.0\.6\./);
  assert.match(graphite, /"head_sha"/);
  assert.match(graphite, /Reviewed SHA: /);
  assert.match(graphite, /if !sha_ok\(head_sha\) \{\s*coverage_complete = false;/);
  assert.match(graphite, /pack_diff_hunks\(raw_diff, MAX_DIFF_CHARS\)/);
  assert.match(graphite, /for packet in review_packets \{/);
  assert.match(graphite, /if map_bool\(collect_out, "diff_truncated", false\) \|\| raw_diff\.len\(\) > MAX_DIFF_CHARS \{\s*coverage_complete = false;/);
  assert.match(graphite, /## Limits/);
  assert.match(graphite, /collapse_group\(ids, confirmed, kept_ids\)/);
  assert.match(graphite, /also /);
  assert.match(graphite, /if map_bool\(out, "residual", false\) \{\s*residuals\.push\(row\);/);
  assert.match(graphite, /## Residuals/);
  assert.match(graphite, /Set residual=true only when the packet diff states the bound and a test in that diff asserts it\./);
  const residualStart = graphite.indexOf('if map_bool(out, "residual", false)');
  const residualBlock = graphite.slice(residualStart, graphite.indexOf('} else {', residualStart));
  assert.doesNotMatch(residualBlock, /kept_ids\.push/);
  const fns = loadReviewFns(['starts_with_text', 'sha_ok', 'diff_hunks', 'pack_diff_hunks', 'collapse_group']);
  assert.equal(fns.sha_ok('a'.repeat(40)), true);
  assert.equal(fns.sha_ok('A'.repeat(40)), false);
  assert.equal(fns.sha_ok('abc'), false);
  const small = 'diff --git a/a.txt b/a.txt\n+a\ndiff --git a/b.txt b/b.txt\n+b';
  const one = fns.pack_diff_hunks(small, 16000);
  assert.equal(one.omitted, 0);
  assert.equal(one.packets.length, 1);
  assert.match(one.packets[0], /a\.txt/);
  assert.match(one.packets[0], /b\.txt/);
  const huge = 'x'.repeat(50);
  const over = fns.pack_diff_hunks(`diff --git a/a.txt b/a.txt\n${huge}\ndiff --git a/b.txt b/b.txt\n${huge}\ndiff --git a/c.txt b/c.txt\n${huge}`, 80);
  assert.equal(over.packets.length, 2);
  assert.equal(over.omitted, 1);
  assert.equal(fns.pack_diff_hunks(`diff --git a/big.txt b/big.txt\n${'y'.repeat(100)}`, 40).omitted, 1);
  const rows = [
    {id: 'f0', file: 'preflight-gate.rhai', line: 231, issue: 'quote split', evidence: 'a'},
    {id: 'f5', file: 'preflight-gate.rhai', line: 223, issue: 'rename split', evidence: 'b'},
  ];
  const collapsed = fns.collapse_group(['f5', 'f0'], rows, ['f0', 'f5', 't0']);
  assert.equal(collapsed.confirmed.length, 1);
  assert.equal(collapsed.confirmed[0].id, 'f0');
  assert.deepEqual(collapsed.confirmed[0].merged_ids, ['f5']);
  assert.deepEqual(collapsed.kept, ['f0', 't0']);
  assert.deepEqual(collapsed.reduced, ['f0']);
  const withThread = fns.collapse_group(['f0', 't0'], rows, ['f0', 'f5', 't0']);
  assert.equal(withThread.collapsed, false);
  assert.deepEqual(withThread.reduced, ['f0', 't0']);
  assert.deepEqual(withThread.kept, ['f0', 'f5', 't0']);
});
