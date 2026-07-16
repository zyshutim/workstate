# Workstate

Workstate is a local macOS shared-working-memory tool for long-running human and Codex collaboration. It keeps project understanding, parallel worklines, meaningful state changes, and exact conversation evidence available across task switches and context compression.

## Product Model

- **L1, Project Graph:** current projects, relationships, activity state, review inbox, and automation budget.
- **L2, Project HEAD:** maintained project context plus a newest-first Git-style workline history.
- **L3, Delta Detail:** one change's result, decisions, runtime evidence, delivery state, and source conversation.

The ingestion path is deliberately separated:

1. A deterministic watcher reads newly completed Codex turns.
2. A Portfolio Router assigns meaningful evidence to one project.
3. An isolated Project Steward proposes the smallest durable project change.
4. A deterministic validator writes ordinary deltas and sends ambiguity or conflicts to Review Inbox.

The current automation mode is `shadow`: it performs real routing and analysis, but does not automatically mutate project state while the policy and token budget are being evaluated.

## Build

Requirements: macOS 14 or later, Swift 6.2, Node.js 18 or later, and an authenticated Codex installation.

```bash
npm install --prefix AgentRuntime
npm run build --prefix AgentRuntime
swift build
swift run WorkstateChecks
./scripts/build-app.sh
```

The built app is written to `dist/Workstate.app`.

## Local Installation

```bash
./scripts/install-daemon.sh
open dist/Workstate.app
```

The daemon is installed under `~/Library/Application Support/Workstate` and registered as the login LaunchAgent `com.timshu.workstate.daemon`.

Project state, conversation evidence, review items, and agent-run usage live outside the repository under `~/.codex/workstate`. They are intentionally excluded from Git.
