---
name: workstate-handoff
description: Load a concise Workstate Context Contract v3 snapshot only when taking over, resuming, or handing off an existing project, task, or Codex thread. Use for 接手, 继续之前的项目, 恢复工作, 无缝衔接, or when the user provides a Workstate project/task id or codex://threads link and expects current project context. Do not run on every turn.
---

# Workstate Handoff

Read Workstate once at the moment of takeover or explicit handoff. Do not refresh it on each turn.

## Context Contract v3

- Formal project cognition is the highest authority.
- Active / waiting worklines are the work to pick up now.
- Pending cognition, open topics, and open semantic bundles are unconfirmed.
- Turning points are the index of key understanding changes.
- The main Markdown stays compact. Its sibling `.sources.json` stores precise `provider / thread / turn / file / byte / message span` pointers for on-demand verification.
- Persistent Owner Codex thread ids do not belong in handoff files; cross-model continuity comes from Workstate persistent state.
- After taking over, first verify the real repository and runtime state before relying on the snapshot.

## Select scope

Use the narrowest known scope:

- Thread link or thread id: `workstate handoff thread <thread-id>`
- Known task/workline id: `workstate handoff task <task-id>`
- Known project id: `workstate handoff project <project-id>`

The default Markdown output is intended to be read directly. Use
`--format json` only when structured processing is necessary.

If the project or route is unknown, fail clearly and ask for the missing
identifier. Do not guess a project from directory names.

## Use the snapshot

- Project summary, confirmed understanding, decisions, and prohibited directions are current project context.
- Worklines describe current work, not a complete historical transcript.
- Open topics are discussions, not confirmed requirements.
- Source IDs in the Markdown resolve through the sibling `.sources.json`. Read that index and raw conversation content only when the current task needs verification.
- If the snapshot conflicts with formal project cognition, follow the formal cognition and treat the handoff as a recovery aid.

After loading, state the scope you recovered and continue the user's task.
Do not rewrite Workstate merely because the snapshot was read.
