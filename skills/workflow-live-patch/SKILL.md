---
name: workflow-live-patch
description: Watch a live Grok workflow run, report failure modes, and patch the saved script before calling the run complete. Use when the user says "monitor the docs refresh workflow for any failure modes or necessary improvements and apply fixes once complete".
when-to-use: monitor the docs refresh workflow, apply fixes once complete, watch a live workflow and patch it
user-invocable: true
origin: learn
disable-model-invocation: false
---

# Workflow live patch

1. Name the workflow file and the live run. Confirm it is the file just edited, not a sibling workflow. That file is the script path the run reports. For docs-refresh it is `<Grok home>/workflows/docs-refresh.rhai` unless the user names another path.
2. Watch the run until it finishes or fails. Record the failing phase, the last log line, and the script path.
3. Do not treat silence as done. Patch only a failure or a gap the user asked to close.
4. Edit that script copy. Smoke-check with validate_only true. Do not invent host APIs.
5. Launch the patched script_path as a new run. Call the job complete only after that run succeeds, or after you report a genuine unsupported capability.
