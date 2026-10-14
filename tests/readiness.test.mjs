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
  assert.match(m[2], /^[a-z_ ()&|]+$/i, 'only boolean expression syntax supported');
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
