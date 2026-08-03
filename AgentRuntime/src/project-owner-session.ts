import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";

export type PersistentProjectOwnerMode =
  | "steward"
  | "batch_steward"
  | "owner_chat"
  | "cognition_draft";

export type ProjectOwnerSessionPlan =
  | { kind: "fresh" }
  | { kind: "resume"; threadId: string };

type ProjectOwnerSessionRegistry = {
  version: 1;
  projects: Record<string, { threadId: string; updatedAt: string }>;
};

export type OwnerChatHistoryItem = {
  role: "user" | "owner";
  text: string;
  timestamp: string;
};

export const resetProjectOwnerSessionMode = "reset_owner_session";

const persistentProjectOwnerModes = new Set<PersistentProjectOwnerMode>([
  "steward",
  "batch_steward",
  "owner_chat",
  "cognition_draft",
]);
const codexThreadIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const maximumBootstrapHistoryMessages = 16;
const maximumBootstrapHistoryBytes = 48 * 1024;

export function isPersistentProjectOwnerMode(mode: string): mode is PersistentProjectOwnerMode {
  return persistentProjectOwnerModes.has(mode as PersistentProjectOwnerMode);
}

export function requireProjectOwnerProjectId(projectId: string): string {
  const trimmed = projectId.trim();
  if (!trimmed) {
    throw new Error("Project Owner session requires a non-empty project id");
  }
  return trimmed;
}

export function requireWorkstateRuntimeRoot(runtimeRoot: string | undefined): string {
  const trimmed = runtimeRoot?.trim() ?? "";
  if (!trimmed) {
    throw new Error("WORKSTATE_RUNTIME_ROOT is required for persistent Project Owner sessions");
  }
  if (!isAbsolute(trimmed)) {
    throw new Error("WORKSTATE_RUNTIME_ROOT must be an absolute path for persistent Project Owner sessions");
  }
  return trimmed;
}

export function projectOwnerCodexHome(runtimeRoot: string): string {
  return join(runtimeRoot, "codex-home");
}

export function projectOwnerSessionRegistryPath(runtimeRoot: string): string {
  return join(runtimeRoot, "project-owner-codex-sessions.json");
}

export function isValidProjectOwnerThreadId(threadId: string): boolean {
  return codexThreadIdPattern.test(threadId);
}

function emptyRegistry(): ProjectOwnerSessionRegistry {
  return { version: 1, projects: {} };
}

function parseRegistry(serialized: string): ProjectOwnerSessionRegistry {
  let parsed: unknown;
  try {
    parsed = JSON.parse(serialized);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Project Owner session registry contains invalid JSON: ${detail}`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Project Owner session registry must be a JSON object");
  }
  const value = parsed as { version?: unknown; projects?: unknown };
  if (value.version !== 1 || !value.projects || typeof value.projects !== "object" || Array.isArray(value.projects)) {
    throw new Error("Project Owner session registry has an unsupported structure");
  }

  const projects: ProjectOwnerSessionRegistry["projects"] = {};
  for (const [projectId, entry] of Object.entries(value.projects)) {
    if (!projectId.trim()) {
      throw new Error("Project Owner session registry contains an empty project id");
    }
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error(`Project Owner session registry entry is invalid for project ${projectId}`);
    }
    const candidate = entry as { threadId?: unknown; updatedAt?: unknown };
    const threadId = candidate.threadId;
    if (typeof threadId !== "string" || !isValidProjectOwnerThreadId(threadId)) {
      throw new Error(`Project Owner session registry has an invalid thread id for project ${projectId}`);
    }
    if (typeof candidate.updatedAt !== "string" || !Number.isFinite(Date.parse(candidate.updatedAt))) {
      throw new Error(`Project Owner session registry has an invalid timestamp for project ${projectId}`);
    }
    projects[projectId] = {
      threadId,
      updatedAt: candidate.updatedAt,
    };
  }
  return { version: 1, projects };
}

async function readRegistry(path: string): Promise<ProjectOwnerSessionRegistry> {
  try {
    return parseRegistry(await readFile(path, "utf8"));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return emptyRegistry();
    }
    throw error;
  }
}

async function writeRegistryAtomically(path: string, registry: ProjectOwnerSessionRegistry): Promise<void> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporaryPath = `${path}.${process.pid}.${randomUUID().toLowerCase()}.tmp`;
  try {
    await writeFile(temporaryPath, `${JSON.stringify(registry)}\n`, { encoding: "utf8", mode: 0o600 });
    await rename(temporaryPath, path);
  } catch (error) {
    await rm(temporaryPath, { force: true }).catch(() => {});
    throw error;
  }
}

export async function planProjectOwnerSession(
  registryPath: string,
  projectId: string,
): Promise<ProjectOwnerSessionPlan> {
  const normalizedProjectId = requireProjectOwnerProjectId(projectId);
  const registry = await readRegistry(registryPath);
  const entry = registry.projects[normalizedProjectId];
  return entry ? { kind: "resume", threadId: entry.threadId } : { kind: "fresh" };
}

export async function recordProjectOwnerSession(
  registryPath: string,
  projectId: string,
  threadId: string,
): Promise<void> {
  const normalizedProjectId = requireProjectOwnerProjectId(projectId);
  if (!isValidProjectOwnerThreadId(threadId)) {
    throw new Error(`Codex returned an invalid Project Owner thread id: ${threadId || "(empty)"}`);
  }
  const registry = await readRegistry(registryPath);
  registry.projects[normalizedProjectId] = {
    threadId,
    updatedAt: new Date().toISOString(),
  };
  await writeRegistryAtomically(registryPath, registry);
}

/**
 * Parent recovery request contract: send { mode: "reset_owner_session", profile,
 * projectId }. It removes only this project's registry entry and returns the removed
 * thread id, if any. Call it only after the runtime reports a stale-session error.
 */
export async function resetProjectOwnerSession(
  registryPath: string,
  projectId: string,
): Promise<{ projectId: string; removedThreadId: string | null }> {
  const normalizedProjectId = requireProjectOwnerProjectId(projectId);
  const registry = await readRegistry(registryPath);
  const removedThreadId = registry.projects[normalizedProjectId]?.threadId ?? null;
  delete registry.projects[normalizedProjectId];
  await writeRegistryAtomically(registryPath, registry);
  return { projectId: normalizedProjectId, removedThreadId };
}

export function projectOwnerCodexArgs(options: {
  plan: ProjectOwnerSessionPlan;
  schemaPath: string;
  responsePath: string;
  model: string;
  reasoning: "low" | "medium" | "high" | "xhigh";
  cwd: string;
}): string[] {
  const common = [
    "--ignore-user-config",
    "--ignore-rules",
    "--skip-git-repo-check",
    "--model", options.model,
    "--config", "approval_policy=\"never\"",
    "--config", `model_reasoning_effort="${options.reasoning}"`,
    "--config", "sandbox_workspace_write.network_access=false",
    "--config", "web_search=\"disabled\"",
    "--output-schema", options.schemaPath,
    "--output-last-message", options.responsePath,
    "--json",
  ];
  if (options.plan.kind === "fresh") {
    return [
      "exec",
      "--sandbox", "read-only",
      "--cd", options.cwd,
      ...common,
      "-",
    ];
  }
  return [
    "exec",
    "resume",
    "--config", "sandbox_mode=\"read-only\"",
    ...common,
    options.plan.threadId,
    "-",
  ];
}

function boundedBootstrapHistory(history: OwnerChatHistoryItem[]): OwnerChatHistoryItem[] {
  const selected: OwnerChatHistoryItem[] = [];
  let totalBytes = 0;
  for (let index = history.length - 1; index >= 0 && selected.length < maximumBootstrapHistoryMessages; index -= 1) {
    const item = history[index];
    const itemBytes = Buffer.byteLength(JSON.stringify(item), "utf8");
    if (itemBytes > maximumBootstrapHistoryBytes - totalBytes) {
      continue;
    }
    selected.push(item);
    totalBytes += itemBytes;
  }
  return selected.reverse();
}

export function ownerChatHistoryPromptContext(
  plan: ProjectOwnerSessionPlan,
  history: OwnerChatHistoryItem[],
): string {
  if (plan.kind === "resume") {
    return "";
  }
  return `BOOTSTRAP CHAT HISTORY (bounded; do not treat it as canonical project state):\n${JSON.stringify(boundedBootstrapHistory(history))}\n`;
}
