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
  focusedWorklineId: string;
  activeWorklines: Array<{
    id: string;
    title: string;
    objective: string;
    status: string;
    stage: string;
  }>;
};

type RuntimeProfile = {
  model: string;
  reasoning: "low" | "medium" | "high" | "xhigh";
};

type RuntimeRequest = {
  profile: RuntimeProfile;
} & (
  | {
      mode: "route";
      segment: Segment;
      projects: ProjectSummary[];
      priorRoute?: { threadID: string; turnID: string; projectID: string; updatedAt: string };
      recentTurns: Segment[];
    }
  | {
      mode: "batch_route";
      segments: Array<Pick<Segment, "id" | "threadID" | "turnID" | "cwd" | "userText" | "timestamp">>;
      projects: ProjectSummary[];
      routeHints: Array<{ threadID: string; projectID: string }>;
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
    }
  | {
      mode: "batch_steward";
      segments: Segment[];
      project: ProjectSummary & {
        currentUnderstanding: string[];
        acceptedDecisions: string[];
        forbiddenDirections: string[];
        openIssues: string[];
        recentDeltas: Array<{ title: string; summary: string; kind: string; timestamp: string }>;
      };
    }
  | {
      mode: "rebuild";
      project: ProjectSummary & {
        currentUnderstanding: string[];
        acceptedDecisions: string[];
        forbiddenDirections: string[];
        openIssues: string[];
      };
      evidencePath: string;
      sourceThreadIds: string[];
    }
  | {
      mode: "distill";
      project: ProjectSummary;
      chunkIndex: number;
      chunkCount: number;
      segments: Segment[];
    }
  | {
      mode: "owner_chat";
      project: ProjectSummary & {
        currentUnderstanding: string[];
        acceptedDecisions: string[];
        forbiddenDirections: string[];
        openIssues: string[];
        recentDeltas: Array<{ title: string; summary: string; kind: string; timestamp: string }>;
        topics: Array<{
          id: string;
          title: string;
          summary: string;
          status: string;
          kind: string;
          disposition: string;
          currentUnderstanding: string;
          proposedDirection: string;
          openQuestions: string[];
        }>;
      };
      history: Array<{ role: "user" | "owner"; text: string; timestamp: string }>;
      message: string;
      activeTopicId: string;
    }
  | {
      mode: "global_chat_route";
      message: string;
      recentMessages: Array<{
        role: "user" | "owner" | "system";
        text: string;
        projectID?: string;
        projectName?: string;
        timestamp: string;
      }>;
      projects: ProjectSummary[];
    }
  | {
      mode: "collaboration_steward";
      collaborationProfile: unknown;
      history: Array<{ role: "user" | "owner"; text: string; timestamp: string }>;
      message: string;
    }
  | {
      mode: "brief";
      dateKey: string;
      sourceRevision: string;
      projects: Array<{
        projectId: string;
        projectName: string;
        projectStatus: string;
        records: Array<{
          id: string;
          kind: "progress" | "confirmed" | "unresolved" | "resume";
          title: string;
          detail: string;
        }>;
      }>;
    }
);

const routeSchema = {
  type: "object",
  properties: {
    action: { type: "string", enum: ["continue_previous", "switch_project", "new_project", "ignore"] },
    projectId: { type: "string" },
    projectName: { type: "string" },
    projectSummary: { type: "string" },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    reason: { type: "string" },
  },
  required: [
    "action",
    "projectId",
    "projectName",
    "projectSummary",
    "confidence",
    "reason",
  ],
  additionalProperties: false,
} as const;

const batchRouteSchema = {
  type: "object",
  properties: {
    routes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          segmentId: { type: "string" },
          action: {
            type: "string",
            enum: ["continue_previous", "switch_project", "new_project", "ignore"],
          },
          projectId: { type: "string" },
          projectName: { type: "string" },
          projectSummary: { type: "string" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          reason: { type: "string" },
        },
        required: [
          "segmentId",
          "action",
          "projectId",
          "projectName",
          "projectSummary",
          "confidence",
          "reason",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["routes"],
  additionalProperties: false,
} as const;

const stewardSchema = {
  type: "object",
  properties: {
    classification: { type: "string", enum: ["no_change", "ordinary_delta"] },
    title: { type: "string" },
    summary: { type: "string" },
    worklineAction: {
      type: "string",
      enum: ["none", "continue_existing", "start_new", "complete_existing"],
    },
    worklineId: { type: "string" },
    worklineTitle: { type: "string" },
    worklineObjective: { type: "string" },
    branchFromWorklineId: { type: "string" },
    isParallel: { type: "boolean" },
    nextFocusedWorklineId: { type: "string" },
    closureDisposition: {
      type: "string",
      enum: ["none", "completed", "future_decision", "awaiting_verification"],
    },
    carryoverTitle: { type: "string" },
    carryoverSummary: { type: "string" },
    carryoverQuestions: { type: "array", items: { type: "string" } },
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
  },
  required: [
    "classification",
    "title",
    "summary",
    "worklineAction",
    "worklineId",
    "worklineTitle",
    "worklineObjective",
    "branchFromWorklineId",
    "isParallel",
    "nextFocusedWorklineId",
    "closureDisposition",
    "carryoverTitle",
    "carryoverSummary",
    "carryoverQuestions",
    "kind",
    "stage",
    "delivery",
    "facts",
    "openIssues",
  ],
  additionalProperties: false,
} as const;

const batchStewardSchema = {
  type: "object",
  properties: {
    decisions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          segmentId: { type: "string" },
          result: stewardSchema,
        },
        required: ["segmentId", "result"],
        additionalProperties: false,
      },
    },
  },
  required: ["decisions"],
  additionalProperties: false,
} as const;

const ownerChatSchema = {
  type: "object",
  properties: {
    reply: { type: "string" },
    topicUpdates: {
      type: "array",
      items: {
        type: "object",
        properties: {
          action: { type: "string", enum: ["create", "update"] },
          topicId: { type: "string" },
          title: { type: "string" },
          summary: { type: "string" },
          status: { type: "string", enum: ["captured", "discussing"] },
          kind: { type: "string", enum: ["product", "frontend", "backend"] },
          disposition: {
            type: "string",
            enum: ["futureDecision", "awaitingVerification"],
          },
          currentUnderstanding: { type: "string" },
          proposedDirection: { type: "string" },
          deferredReason: { type: "string" },
          revisitTrigger: { type: "string" },
          openQuestions: { type: "array", items: { type: "string" } },
          noteKind: { type: "string", enum: ["origin", "ownerAnalysis", "userCorrection"] },
          noteTitle: { type: "string" },
          noteDetail: { type: "string" },
        },
        required: [
          "action", "topicId", "title", "summary", "status", "kind", "disposition",
          "currentUnderstanding", "proposedDirection", "deferredReason",
          "revisitTrigger", "openQuestions", "noteKind", "noteTitle", "noteDetail",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["reply", "topicUpdates"],
  additionalProperties: false,
} as const;

const briefSchema = {
  type: "object",
  properties: {
    overview: { type: "string", minLength: 1, maxLength: 360 },
    projectSummaries: {
      type: "array",
      items: {
        type: "object",
        properties: {
          projectId: { type: "string" },
          summary: { type: "string", minLength: 1, maxLength: 240 },
        },
        required: ["projectId", "summary"],
        additionalProperties: false,
      },
    },
    nextStep: { type: "string", maxLength: 240 },
  },
  required: ["overview", "projectSummaries", "nextStep"],
  additionalProperties: false,
} as const;

const evidenceIds = { type: "array", items: { type: "string" } } as const;
const evidenceStatement = {
  type: "object",
  properties: {
    text: { type: "string" },
    evidenceIds,
  },
  required: ["text", "evidenceIds"],
  additionalProperties: false,
} as const;

const distillSchema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          category: {
            type: "string",
            enum: ["understanding", "objectModel", "decision", "forbiddenDirection", "openIssue", "worklineSignal", "delta", "supersession"],
          },
          title: { type: "string" },
          summary: { type: "string" },
          timestamp: { type: "string" },
          worklineHint: { type: "string" },
          status: { type: "string", enum: ["none", "observed", "confirmed", "superseded", "prohibited", "open"] },
          kind: {
            type: "string",
            enum: ["none", "contextUpdate", "investigation", "decision", "implementation", "verification", "accepted", "integrated", "operational", "interruption", "resumed", "completed"],
          },
          stage: {
            type: "string",
            enum: ["none", "intake", "reconstruction", "audit", "modeling", "confirmation", "implementation", "verification", "acceptance", "integration", "completed"],
          },
          delivery: {
            type: "string",
            enum: ["none", "unchanged", "changed", "checked", "rendered", "userAccepted", "integrated", "published"],
          },
          facts: { type: "array", items: { type: "string" } },
          decisions: { type: "array", items: { type: "string" } },
          evidenceIds,
        },
        required: ["category", "title", "summary", "timestamp", "worklineHint", "status", "kind", "stage", "delivery", "facts", "decisions", "evidenceIds"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
} as const;

const rebuildSchema = {
  type: "object",
  properties: {
    projectId: { type: "string" },
    status: { type: "string", enum: ["active", "waiting", "parked", "completed"] },
    currentSummary: { type: "string" },
    purpose: { type: "string" },
    inScope: { type: "array", items: { type: "string" } },
    outOfScope: { type: "array", items: { type: "string" } },
    objectModel: { type: "array", items: evidenceStatement },
    understanding: {
      type: "array",
      items: {
        type: "object",
        properties: {
          text: { type: "string" },
          status: { type: "string", enum: ["observed", "confirmed"] },
          evidenceIds,
        },
        required: ["text", "status", "evidenceIds"],
        additionalProperties: false,
      },
    },
    acceptedDecisions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          text: { type: "string" },
          rationale: { type: "string" },
          evidenceIds,
        },
        required: ["text", "rationale", "evidenceIds"],
        additionalProperties: false,
      },
    },
    forbiddenDirections: { type: "array", items: evidenceStatement },
    openIssues: { type: "array", items: evidenceStatement },
    worklines: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          objective: { type: "string" },
          status: { type: "string", enum: ["active", "waiting", "parked", "completed", "abandoned"] },
          stage: {
            type: "string",
            enum: ["intake", "reconstruction", "audit", "modeling", "confirmation", "implementation", "verification", "acceptance", "integration", "completed"],
          },
          startedAt: { type: "string" },
          updatedAt: { type: "string" },
          completedAt: { type: "string" },
          tags: { type: "array", items: { type: "string" } },
          evidenceIds,
        },
        required: ["id", "title", "objective", "status", "stage", "startedAt", "updatedAt", "completedAt", "tags", "evidenceIds"],
        additionalProperties: false,
      },
    },
    deltas: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          worklineId: { type: "string" },
          timestamp: { type: "string" },
          title: { type: "string" },
          summary: { type: "string" },
          kind: {
            type: "string",
            enum: ["contextUpdate", "investigation", "decision", "implementation", "verification", "accepted", "integrated", "operational", "interruption", "resumed", "completed"],
          },
          stage: {
            type: "string",
            enum: ["intake", "reconstruction", "audit", "modeling", "confirmation", "implementation", "verification", "acceptance", "integration", "completed"],
          },
          delivery: {
            type: "string",
            enum: ["unchanged", "changed", "checked", "rendered", "userAccepted", "integrated", "published"],
          },
          facts: { type: "array", items: { type: "string" } },
          decisions: { type: "array", items: { type: "string" } },
          evidenceIds,
        },
        required: ["id", "worklineId", "timestamp", "title", "summary", "kind", "stage", "delivery", "facts", "decisions", "evidenceIds"],
        additionalProperties: false,
      },
    },
  },
  required: [
    "projectId", "status", "currentSummary", "purpose", "inScope", "outOfScope", "objectModel",
    "understanding", "acceptedDecisions", "forbiddenDirections", "openIssues", "worklines", "deltas",
  ],
  additionalProperties: false,
} as const;

function constrainedRebuildSchema(distilledCorpus: string): object {
  const allowedIds = new Set<string>();
  for (const line of distilledCorpus.split("\n")) {
    if (!line.trim()) continue;
    const chunk = JSON.parse(line) as { items?: Array<{ evidenceIds?: string[] }> };
    for (const item of chunk.items ?? []) {
      for (const id of item.evidenceIds ?? []) allowedIds.add(id);
    }
  }
  if (allowedIds.size === 0) throw new Error("Distilled corpus contains no retained evidence ids");

  const schema = JSON.parse(JSON.stringify(rebuildSchema)) as Record<string, unknown>;
  const constrain = (node: unknown): void => {
    if (!node || typeof node !== "object") return;
    const record = node as Record<string, unknown>;
    const properties = record.properties as Record<string, unknown> | undefined;
    const evidence = properties?.evidenceIds as Record<string, unknown> | undefined;
    const items = evidence?.items as Record<string, unknown> | undefined;
    if (items) items.enum = Array.from(allowedIds).sort();
    for (const value of Object.values(record)) constrain(value);
};

  constrain(schema);
  return schema;
}

const globalChatRouteSchema = {
  type: "object",
  properties: {
    projectId: { type: "string" },
    reason: { type: "string" },
  },
  required: ["projectId", "reason"],
  additionalProperties: false,
} as const;

const collaborationStewardSchema = {
  type: "object",
  properties: {
    reply: { type: "string" },
    mutations: {
      type: "array",
      items: {
        type: "object",
        properties: {
          action: { type: "string", enum: ["create", "update", "supersede"] },
          authority: { type: "string", enum: ["explicit_user", "inference"] },
          id: { type: "string" },
          kind: {
            type: "string",
            enum: ["userPersona", "collaboratorPersona", "preference", "rule", "loop", "prohibition"],
          },
          status: { type: "string", enum: ["active", "candidate", "superseded"] },
          title: { type: "string" },
          detail: { type: "string" },
          scope: { type: "string" },
          evidence: { type: "array", items: { type: "string" } },
          supersedesId: { type: "string" },
        },
        required: [
          "action", "authority", "id", "kind", "status", "title", "detail", "scope", "evidence", "supersedesId",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["reply", "mutations"],
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

Do not inspect the filesystem, use tools, summarize the project, propose project-state changes, or classify worklines inside a project.
One Codex task may switch projects between turns, but short or referential follow-ups usually continue the prior semantic scope. Route by actual meaning, not merely cwd.
Use continue_previous when the new turn continues, clarifies, corrects, or implements the prior routed work, especially when the turn is not independently understandable. Use switch_project only when the current evidence positively establishes a different existing project. Use new_project when it establishes durable work that does not belong to any existing project. Use ignore only for casual, personal, or one-off content with no project consequence.
You own this decision. Choose the best semantic match from the evidence instead of asking the user to classify it. For continue_previous, projectId must equal PRIOR ROUTE.projectID. For switch_project, projectId must identify the selected existing project. For new_project, return a stable kebab-case projectId, a concise projectName, and a one-sentence projectSummary. Otherwise leave projectName and projectSummary empty.

PROJECTS:
${JSON.stringify(request.projects)}

PRIOR ROUTE:
${JSON.stringify(request.priorRoute ?? null)}

RECENT TURNS IN THIS THREAD:
${JSON.stringify(request.recentTurns)}

TURN:
${JSON.stringify(request.segment)}
`;
}

function batchRoutePrompt(request: Extract<RuntimeRequest, { mode: "batch_route" }>): string {
  return `You are Workstate's Portfolio Router performing a cold-start import. Classify every supplied completed Codex turn while preserving their order.

Return exactly one route for every segmentId and no duplicates. A single Codex task may change projects between turns. Use the ordered turns in the same thread to resolve short follow-ups. A route hint is the user's initial belief, not a permanent lock.
Use continue_previous only when a prior turn in this batch or a route hint establishes that project. Use switch_project for a different existing project. Use new_project only for durable work that fits none of the supplied projects, and reuse the same stable projectId when several turns establish the same new project. Use ignore only for content with no project consequence.
Do not inspect files, use tools, summarize project internals, or create worklines.

PROJECTS:
${JSON.stringify(request.projects)}

USER ROUTE HINTS:
${JSON.stringify(request.routeHints)}

ORDERED TURNS:
${JSON.stringify(request.segments)}
`;
}

function stewardPrompt(request: Extract<RuntimeRequest, { mode: "steward" }>): string {
  return `You are the Project Steward for exactly one project. Compare one completed Codex turn with the supplied Project HEAD.

Do not inspect the filesystem or use tools. Do not rewrite the whole project model. Return only the smallest durable state change.
Use no_change for chatter, planning with no accepted consequence, repeated information, and intermediate debugging.
Use ordinary_delta for objective implementation, verification, operational progress, and decisions explicitly made by the user in this turn.
When evidence corrects earlier project understanding, record the correction as an ordinary_delta. Do not ask the user to classify or reconfirm it.
Never infer userAccepted, integrated, rendered, or published without direct evidence in the turn.
Keep title short and summary to one sentence. Retain at most four facts and two open issues.

You also own the project-internal workline lifecycle. A workline is a bounded stream with an independent purpose and completion condition, not a document section, product module, conversation, or individual turn.
- Use continue_existing when the turn advances an existing supplied workline.
- Use start_new when the turn clearly interrupts or diverges into an independently completable scope. A phrase such as "slightly interrupting" is only a signal; the semantic purpose and completion condition decide.
- Use complete_existing when this turn actually closes the bounded scope. Do not complete work merely because discussion paused.
- Use none only for no_change or a project-wide delta that genuinely belongs to no bounded workline.

The project has one explicit focused workline. Changing focus does not automatically mean parallel work.
- Set isParallel true only when the evidence shows the previous focused workline is still being actively advanced at the same time.
- Otherwise set isParallel false. When the turn moves to another workline, the previous focus ends rather than remaining parked.
- For complete_existing, set nextFocusedWorklineId to the workline that should become the current focus, or empty when no workline is current.
- For every other action, leave nextFocusedWorklineId empty.

Whenever a workline ends, classify what remains:
- completed: its bounded result is settled and nothing needs later attention;
- awaiting_verification: implementation or action ended, but success, acceptance, external feedback, or a later result is still unknown;
- future_decision: the current execution ended, but a possible future direction still needs a decision;
- none: no workline ends in this decision.
Use a non-none closureDisposition when complete_existing closes worklineId, or when a non-parallel focus switch ends the previous focused workline. For awaiting_verification and future_decision, provide a concise carryoverTitle, carryoverSummary, and any carryoverQuestions. Leave carryover fields empty for none and completed.

Connected decisions under one purpose stay together. For example, display/highlight rules and folding rules are one workline when both are parts of confirming and optimizing the same material-graph interaction model. A separate data-mapping defect with its own diagnosis and fix is a different workline.

For continue_existing and complete_existing, worklineId must exactly match a supplied workline. For start_new, return a stable project-prefixed kebab-case id, concise title and objective, plus branchFromWorklineId identifying the semantic parent scope; leave branchFromWorklineId empty only when branching from the project itself. Empty unused workline strings are required for none. Never reuse the broad parent workline merely because no narrower one exists.

PROJECT HEAD:
${JSON.stringify(request.project)}

NEW EVIDENCE:
${JSON.stringify(request.segment)}
`;
}

function batchStewardPrompt(request: Extract<RuntimeRequest, { mode: "batch_steward" }>): string {
  return `You are the Project Steward for exactly one project. Process every supplied completed Codex turn in chronological order while maintaining the evolving workline state.

Return exactly one decision for every segmentId, in the same order, with no duplicates. Each decision follows the same rules as the single-turn Project Steward:
- no_change for chatter, repetition, or intermediate debugging with no durable consequence;
- ordinary_delta for durable decisions, implementation, verification, operations, or corrections;
- worklines are bounded streams with independent purposes and completion conditions, not pages, modules, conversations, or turns;
- continue the same workline when the purpose remains the same;
- start a new workline only for independently completable scope;
- complete a workline when its bounded deliverable closes, even when user acceptance remains separately unverified;
- changing focus is not parallel work. Set isParallel true only when evidence shows both scopes remain actively advancing;
- when focus switches and isParallel is false, the previous focus ends; use closureDisposition to say whether it is settled or leaves a future-decision / verification topic;
- for complete_existing, nextFocusedWorklineId identifies the workline that becomes current, or is empty when none does.
- closureDisposition is none when no workline ends. It is completed for settled work, awaiting_verification when a result or acceptance is still unknown, and future_decision when later product choice remains.
- for awaiting_verification and future_decision, provide concise carryoverTitle, carryoverSummary, and carryoverQuestions; otherwise leave them empty.

Simulate the consequences of each earlier decision before deciding the next one. A later turn may continue, complete, or switch away from a workline created by an earlier turn in this same batch. Use stable project-prefixed ids for new worklines. Do not inspect files or use tools. Never infer user acceptance, rendered behavior, integration, or publication without direct evidence.

PROJECT HEAD:
${JSON.stringify(request.project)}

ORDERED NEW EVIDENCE:
${JSON.stringify(request.segments)}
`;
}

function ownerChatPrompt(request: Extract<RuntimeRequest, { mode: "owner_chat" }>): string {
  return `You are the Project Owner for exactly one project. You share responsibility for the product with the user and maintain the same project-level understanding supplied below.

Talk with the user directly in Chinese. Help them reason about unfinished topics, future todos, product direction, tradeoffs, and priorities. Use the project HEAD as durable memory, and use the conversation history for continuity.

Do not behave like a passive recorder or a generic assistant. Form an independent view, identify contradictions, and distinguish confirmed project facts from your inference. Keep the reply concise enough for an ongoing conversation.

The user's new ideas, possible directions, future work, and unresolved product questions are NOT confirmed project facts. Discuss them and persist them as captured or discussing topics. Use futureDecision when the user has not decided whether to do something. Use awaitingVerification only when work already happened but its completion, result, acceptance, or external feedback remains unknown. Never label a new proposal as confirmed. Only the user-facing confirmation UI can promote a topic into the formal project flow; you cannot confirm decisions or create tasks.

Return topicUpdates when this turn creates durable unfinished work or materially changes an existing topic. Ordinary questions or chatter may return an empty array. Prefer updating ACTIVE TOPIC when supplied. Otherwise match an existing topic semantically before creating one. A single user turn should normally create at most one evolving topic: keep connected ideas together as one topic with multiple questions instead of fragmenting them. Split only when the user explicitly identifies independent backlog items. A correction must update the topic and append a userCorrection note. Use a stable kebab-case topicId for creation. Do not claim in reply that anything was approved, implemented, or scheduled.

PROJECT HEAD:
${JSON.stringify(request.project)}

OWNER CONVERSATION HISTORY:
${JSON.stringify(request.history)}

ACTIVE TOPIC:
${request.activeTopicId || "none"}

USER MESSAGE:
${request.message}
`;
}

function globalChatRoutePrompt(request: Extract<RuntimeRequest, { mode: "global_chat_route" }>): string {
  return `You route one global Workstate chat message to exactly one existing Project Owner.

Choose the project whose durable purpose and current summary best match the user's message. Use recent messages only for conversational continuity. Return an exact existing projectId. Do not analyze the product question, update project state, create a project, or reply to the user. Keep reason to one short Chinese sentence.

PROJECTS:
${JSON.stringify(request.projects)}

RECENT GLOBAL CHAT:
${JSON.stringify(request.recentMessages)}

USER MESSAGE:
${request.message}
`;
}

function collaborationStewardPrompt(request: Extract<RuntimeRequest, { mode: "collaboration_steward" }>): string {
  return `You maintain a provider-neutral collaboration profile shared by the user and future AI collaborators.

Talk directly in concise Chinese. Help the user inspect and refine Persona, preferences, rules, loops, and prohibitions at a general level. Do not turn project-specific details or a one-off mood into universal rules.

Mutation authority:
- An explicit user instruction, correction, approval, or prohibition may create or update an active entry.
- Your own inference may only create a candidate entry.
- Set authority to explicit_user only when the current user message itself directly states, approves, revises, or rejects the rule. Otherwise set inference.
- Never silently supersede an active entry. Do it only when the user explicitly revises or rejects it.
- Use stable kebab-case ids. For update, preserve the existing id. Keep evidence as short quotes or exact source labels supplied in the conversation.
- Ordinary discussion may return no mutations.

CURRENT PROFILE:
${JSON.stringify(request.collaborationProfile)}

RECENT CONVERSATION:
${JSON.stringify(request.history)}

USER MESSAGE:
${request.message}
`;
}

function briefPrompt(request: Extract<RuntimeRequest, { mode: "brief" }>): string {
  return `You are Workstate's Brief Composer. Turn one activity day's structured project records into a concise Chinese narrative that helps the user resume work.

Do not inspect the filesystem or use tools. Use only the supplied records. Do not invent implementation, verification, acceptance, integration, publication, decisions, blockers, or next steps.
Write for a person scanning a 600px-wide macOS panel:
- overview: two or three natural sentences that synthesize the day's main movement across projects; do not list counts or repeat every record;
- projectSummaries: exactly one entry for every supplied projectId, preserving the exact id, with one or two natural sentences about what changed and what it means;
- nextStep: one or two direct sentences derived only from unresolved or resume records; return an empty string when no such record exists.

Do not use Markdown headings, bullets, internal ids, timestamps, process jargon, or phrases such as "the records show". Distinguish actual progress from confirmed decisions and unfinished work. Prefer concrete product language over generic status language.

ACTIVITY DATE:
${request.dateKey}

SOURCE REVISION:
${request.sourceRevision}

PROJECT RECORDS:
${JSON.stringify(request.projects)}
`;
}

function distillPrompt(request: Extract<RuntimeRequest, { mode: "distill" }>): string {
  return `You are Workstate's Evidence Distiller for exactly one project. Read every completed Codex turn in this chronological chunk once and extract only durable project evidence. Do not invoke tools.

Retain:
- corrections to project understanding or object relationships;
- explicit user decisions, prohibitions, and unresolved issues;
- signals that identify a semantic workline;
- meaningful state changes: investigation, implementation, verification, visible rendering, user acceptance, integration, or publication;
- later evidence that supersedes an earlier conclusion.

A single turn may produce multiple retained items. If it both establishes a decision and reports that code/UI was implemented, checked, rendered, accepted, integrated, or published, emit a decision item and a separate delta item. Do not hide an implementation milestone inside a decision-only item.

Do not create an item for ordinary discussion, repeated status narration, shell/build housekeeping, cache cleanup, port/process work, or Workstate bookkeeping unless it materially changes product delivery. A request to update Workstate is secondary documentation, not user acceptance of the underlying product.

Every retained item must cite only exact ids from the supplied segments and must copy a non-empty original timestamp from one of those cited segments. Keep display text clean and put ids only in evidenceIds. Use a concise worklineHint describing semantic scope, not a generated id. Empty optional semantics must use "none", empty strings, or empty arrays as required by the schema.

Delivery meanings are strict:
- unchanged: understanding or investigation only;
- changed: code or data changed but has not been checked;
- checked: tests, audit, or deterministic checks passed;
- rendered: the real UI was visibly rendered and inspected;
- userAccepted: the user explicitly accepted that exact product result;
- integrated: the change entered the canonical branch or repository;
- published: deployed, released to users, or published as a public artifact. A git push alone is not published.

PROJECT:
${JSON.stringify(request.project)}

CHUNK ${request.chunkIndex + 1} OF ${request.chunkCount}:
${JSON.stringify(request.segments)}
`;
}

function rebuildPrompt(
  request: Extract<RuntimeRequest, { mode: "rebuild" }>,
  distilledCorpus: string,
): string {
  return `You are the isolated Project Steward responsible for rebuilding exactly one Workstate project from its complete Codex history.

The complete chronological evidence distillation is embedded below. Deterministic orchestration already sent every original completed turn through exactly one distillation chunk. Each retained item cites exact original evidence ids. Read every distilled chunk and item. Do not invoke tools or reopen files.

The existing project data below is a fallible legacy candidate, not authority. Reconstruct the canonical project state from the evidence. Latest explicit user corrections supersede earlier proposals. Separate product state from operational housekeeping: cache cleanup, process restarts, and incidental debugging must not become the Project HEAD or a durable workline unless they materially changed delivery state.

Produce:
- a concise current Project HEAD;
- the durable object model, confirmed decisions, prohibited directions, and unresolved issues;
- a small set of semantic worklines, not one workline per conversation or implementation detail;
- only meaningful deltas that explain state transitions, decisions, implementation, verification, acceptance, integration, or publication.

Every object-model item, understanding item, decision, prohibited direction, open issue, workline, and delta must reference one or more exact evidence ids from the corpus. Never invent an id. Keep display text clean: never embed citation syntax, evidence ids, timestamps, or source locators inside text fields; put ids only in evidenceIds. Use kebab-case ids prefixed with the project id. Use ISO-8601 timestamps copied from evidence. Active work must remain active even if earlier milestones completed. A discussion is not implementation, rendered behavior, user acceptance, integration, or publication.

A workline is a bounded stream of work that branches and later merges, not a permanent product module or issue category. Mark a historical workline completed once its accepted or integrated milestone closed that stream. A later residual issue does not keep the entire historical stream active; create or retain a separate active verification/recovery workline only when evidence shows that work is currently being pursued. Keep the number of concurrent active worklines small and evidence-based.

Do not collapse a completed project's entire history into one final release delta when the evidence contains distinct durable milestones. Preserve a small chronological sequence that explains major product decisions, implementation convergence, visible/user acceptance, and publication. These deltas belong inside the bounded workline and should remain selective rather than turn-by-turn.

Every workline must have non-empty startedAt and updatedAt copied from cited evidence. Its startedAt must be at or before every delta assigned to it, and updatedAt must be at or after every assigned delta. Include the earliest and latest assigned delta evidence in the workline evidenceIds, use those boundary timestamps, and ensure completedAt is also at or after every assigned delta. A completed workline must have non-empty completedAt; only an unfinished workline may use an empty completedAt.

Delivery meanings are strict:
- unchanged: understanding or investigation only;
- changed: code or data changed but has not been checked;
- checked: tests, audit, or deterministic checks passed;
- rendered: the real UI was visibly rendered and inspected;
- userAccepted: the user explicitly accepted that exact product result, not merely asked Workstate to record it;
- integrated: the change entered the canonical branch or repository;
- published: the result was deployed, released to users, or published as a public artifact. A git push alone is not published.

PROJECT CANDIDATE:
${JSON.stringify(request.project)}

ALLOWED SOURCE THREADS:
${JSON.stringify(request.sourceThreadIds)}

COMPLETE DISTILLED EVIDENCE:
${distilledCorpus}
`;
}

async function main(): Promise<void> {
  const request = await readRequest();
  const distilledCorpus = request.mode === "rebuild"
    ? await readFile(request.evidencePath, "utf8")
    : undefined;
  const runtimeProfile = request.profile;
  const codex = new Codex();
  const thread = codex.startThread({
    model: runtimeProfile.model,
    workingDirectory: process.cwd(),
    skipGitRepoCheck: true,
    sandboxMode: "read-only",
    approvalPolicy: "never",
    networkAccessEnabled: false,
    modelReasoningEffort: runtimeProfile.reasoning,
  });
  const prompt = request.mode === "route"
    ? routePrompt(request)
    : request.mode === "batch_route"
      ? batchRoutePrompt(request)
    : request.mode === "steward"
      ? stewardPrompt(request)
    : request.mode === "batch_steward"
      ? batchStewardPrompt(request)
      : request.mode === "collaboration_steward"
        ? collaborationStewardPrompt(request)
      : request.mode === "global_chat_route"
        ? globalChatRoutePrompt(request)
      : request.mode === "owner_chat"
        ? ownerChatPrompt(request)
      : request.mode === "brief"
        ? briefPrompt(request)
      : request.mode === "distill"
        ? distillPrompt(request)
        : rebuildPrompt(request, distilledCorpus!);
  const outputSchema = request.mode === "route"
    ? routeSchema
    : request.mode === "batch_route"
      ? batchRouteSchema
    : request.mode === "steward"
      ? stewardSchema
    : request.mode === "batch_steward"
      ? batchStewardSchema
      : request.mode === "collaboration_steward"
        ? collaborationStewardSchema
      : request.mode === "global_chat_route"
        ? globalChatRouteSchema
      : request.mode === "owner_chat"
        ? ownerChatSchema
      : request.mode === "brief"
        ? briefSchema
      : request.mode === "distill"
        ? distillSchema
        : constrainedRebuildSchema(distilledCorpus!);
  const turn = await thread.run(
    prompt,
    { outputSchema },
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
