import { Codex } from "@openai/codex-sdk";
import { readFile } from "node:fs/promises";
import process from "node:process";

type Segment = {
  id: string;
  threadID: string;
  turnID: string;
  sourcePath: string;
  cwd: string;
  userText: string;
  assistantText: string;
  timestamp: string;
};

type ProjectSummary = {
  id: string;
  name: string;
  summary: string;
  purpose: string;
  status: string;
  activeWorklines: Array<{
    id: string;
    title: string;
    objective: string;
    status: string;
    stage: string;
  }>;
};

type RuntimeRequest =
  | {
      mode: "route";
      segment: Segment;
      projects: ProjectSummary[];
    }
  | {
      mode: "steward";
      segment: Segment;
      project: ProjectSummary & {
        currentUnderstanding: string[];
        acceptedDecisions: string[];
        forbiddenDirections: string[];
        openIssues: string[];
        recentDeltas: Array<{ title: string; summary: string; kind: string; timestamp: string }>;
      };
    };

const routeSchema = {
  type: "object",
  properties: {
    action: { type: "string", enum: ["existing_project", "candidate_project", "ignore", "ambiguous"] },
    projectId: { type: "string" },
    worklineHint: { type: "string" },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    reason: { type: "string" },
  },
  required: ["action", "projectId", "worklineHint", "confidence", "reason"],
  additionalProperties: false,
} as const;

const stewardSchema = {
  type: "object",
  properties: {
    classification: { type: "string", enum: ["no_change", "ordinary_delta", "review_required"] },
    title: { type: "string" },
    summary: { type: "string" },
    worklineId: { type: "string" },
    kind: {
      type: "string",
      enum: [
        "contextUpdate",
        "investigation",
        "decision",
        "implementation",
        "verification",
        "accepted",
        "integrated",
        "operational",
        "interruption",
        "resumed",
        "completed",
      ],
    },
    stage: {
      type: "string",
      enum: [
        "intake",
        "reconstruction",
        "audit",
        "modeling",
        "confirmation",
        "implementation",
        "verification",
        "acceptance",
        "integration",
        "completed",
      ],
    },
    delivery: {
      type: "string",
      enum: ["unchanged", "changed", "checked", "rendered", "userAccepted", "integrated", "published"],
    },
    facts: { type: "array", items: { type: "string" } },
    openIssues: { type: "array", items: { type: "string" } },
    review: {
      type: "object",
      properties: {
        kind: {
          type: "string",
          enum: ["ambiguousRouting", "candidateProject", "projectStructure", "understandingConflict", "decisionConflict"],
        },
        reason: { type: "string" },
        previousValue: { type: "string" },
        proposedValue: { type: "string" },
        proposedChanges: { type: "array", items: { type: "string" } },
      },
      required: ["kind", "reason", "previousValue", "proposedValue", "proposedChanges"],
      additionalProperties: false,
    },
  },
  required: [
    "classification",
    "title",
    "summary",
    "worklineId",
    "kind",
    "stage",
    "delivery",
    "facts",
    "openIssues",
    "review",
  ],
  additionalProperties: false,
} as const;

async function readRequest(): Promise<RuntimeRequest> {
  const path = process.argv[2];
  const input = path ? await readFile(path, "utf8") : await readStdin();
  return JSON.parse(input) as RuntimeRequest;
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

function routePrompt(request: Extract<RuntimeRequest, { mode: "route" }>): string {
  return `You are Workstate's Portfolio Router. Your only job is to decide where one completed Codex turn belongs.

Do not inspect the filesystem, use tools, summarize the project, or propose project-state changes.
One Codex task may switch projects between turns. Route this turn by its actual semantic scope, not merely cwd.
Use existing_project only when one project is a clear match. Use candidate_project only for durable new work. Use ignore for casual or one-off content. Use ambiguous when evidence is insufficient.

PROJECTS:
${JSON.stringify(request.projects)}

TURN:
${JSON.stringify(request.segment)}
`;
}

function stewardPrompt(request: Extract<RuntimeRequest, { mode: "steward" }>): string {
  return `You are the Project Steward for exactly one project. Compare one completed Codex turn with the supplied Project HEAD.

Do not inspect the filesystem or use tools. Do not rewrite the whole project model. Return only the smallest durable state change.
Use no_change for chatter, planning with no accepted consequence, repeated information, and intermediate debugging.
Use ordinary_delta for objective implementation, verification, operational progress, and decisions explicitly made by the user in this turn.
Use review_required only for an inference that would overwrite accepted understanding, a contradiction, ambiguous structure, project creation/split/merge, or insufficient evidence. Do not ask the user to reconfirm an explicit decision already present in the turn.
Never infer userAccepted, integrated, rendered, or published without direct evidence in the turn.
When review is unused, return empty strings and an empty proposedChanges array; use understandingConflict as its placeholder kind.

PROJECT HEAD:
${JSON.stringify(request.project)}

NEW EVIDENCE:
${JSON.stringify(request.segment)}
`;
}

async function main(): Promise<void> {
  const request = await readRequest();
  const codex = new Codex();
  const thread = codex.startThread({
    workingDirectory: process.cwd(),
    skipGitRepoCheck: true,
    sandboxMode: "read-only",
    approvalPolicy: "never",
    networkAccessEnabled: false,
    modelReasoningEffort: request.mode === "route" ? "low" : "medium",
  });
  const turn = await thread.run(
    request.mode === "route" ? routePrompt(request) : stewardPrompt(request),
    { outputSchema: request.mode === "route" ? routeSchema : stewardSchema },
  );
  const result = JSON.parse(turn.finalResponse) as unknown;
  process.stdout.write(
    JSON.stringify({
      mode: request.mode,
      runtimeThreadId: thread.id,
      usage: turn.usage,
      result,
    }),
  );
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
