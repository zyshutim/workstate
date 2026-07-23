---
name: workstate-handoff
description: Load a concise Workstate context snapshot when taking over, resuming, or handing off an existing project, task, or Codex thread. Use for 接手, 继续之前的项目, 恢复工作, 无缝衔接, or when the user provides a Workstate project/task id or codex://threads link and expects current project context. Do not run on every turn.
---

# Workstate Handoff

Read Workstate once at the moment of takeover. Do not refresh it on each turn.

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
- Source pointers are available for targeted verification. Read raw conversation content only when the current task needs it.

After loading, state the scope you recovered and continue the user's task.
Do not rewrite Workstate merely because the snapshot was read.
