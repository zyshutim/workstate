import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  ownerChatHistoryPromptContext,
  planProjectOwnerSession,
  projectOwnerCodexArgs,
  recordProjectOwnerSession,
  resetProjectOwnerSession,
} from "./project-owner-session.js";

const firstThread = "11111111-1111-1111-1111-111111111111";
const secondThread = "22222222-2222-2222-2222-222222222222";

test("registry resumes valid entries, rejects corruption, and resets one project", async () => {
  const root = await mkdtemp(join(tmpdir(), "workstate-owner-session-test-"));
  const registryPath = join(root, "project-owner-codex-sessions.json");
  try {
    assert.deepEqual(await planProjectOwnerSession(registryPath, "alpha"), { kind: "fresh" });
    await recordProjectOwnerSession(registryPath, "alpha", firstThread);
    await recordProjectOwnerSession(registryPath, "beta", secondThread);
    const persisted = JSON.parse(await readFile(registryPath, "utf8")) as {
      projects: Record<string, { threadId: string }>;
    };
    assert.equal(persisted.projects.alpha.threadId, firstThread);
    assert.equal(persisted.projects.beta.threadId, secondThread);
    assert.deepEqual(await planProjectOwnerSession(registryPath, "alpha"), {
      kind: "resume",
      threadId: firstThread,
    });

    const reset = await resetProjectOwnerSession(registryPath, "alpha");
    assert.deepEqual(reset, { projectId: "alpha", removedThreadId: firstThread });
    assert.deepEqual(await planProjectOwnerSession(registryPath, "alpha"), { kind: "fresh" });
    assert.deepEqual(await planProjectOwnerSession(registryPath, "beta"), {
      kind: "resume",
      threadId: secondThread,
    });

    await writeFile(registryPath, JSON.stringify({
      version: 1,
      projects: { beta: { threadId: "not-a-codex-thread", updatedAt: "now" } },
    }));
    await assert.rejects(
      planProjectOwnerSession(registryPath, "beta"),
      /invalid thread id for project beta/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("fresh and resumed Owner invocations select different arguments and chat history", () => {
  const base = {
    schemaPath: "/tmp/schema.json",
    responsePath: "/tmp/response.json",
    model: "gpt-5.6",
    reasoning: "medium" as const,
    cwd: "/tmp/workspace",
  };
  const freshArgs = projectOwnerCodexArgs({ plan: { kind: "fresh" }, ...base });
  const resumeArgs = projectOwnerCodexArgs({
    plan: { kind: "resume", threadId: firstThread },
    ...base,
  });
  assert.deepEqual(freshArgs.slice(0, 6), ["exec", "--sandbox", "read-only", "--cd", "/tmp/workspace", "--ignore-user-config"]);
  assert.deepEqual(resumeArgs.slice(0, 5), ["exec", "resume", "--config", "sandbox_mode=\"read-only\"", "--ignore-user-config"]);
  assert.equal(resumeArgs.at(-2), firstThread);
  assert.ok(!resumeArgs.includes("--ephemeral"));

  const history = Array.from({ length: 20 }, (_, index) => ({
    role: index % 2 === 0 ? "user" as const : "owner" as const,
    text: `prior-message-${index}`,
    timestamp: `2026-07-31T00:00:${String(index).padStart(2, "0")}Z`,
  }));
  const freshContext = ownerChatHistoryPromptContext({ kind: "fresh" }, history);
  const resumedContext = ownerChatHistoryPromptContext({ kind: "resume", threadId: firstThread }, history);
  assert.match(freshContext, /prior-message-19/);
  assert.doesNotMatch(freshContext, /prior-message-0/);
  assert.equal(resumedContext, "");
});
