import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  appendFileSync,
  constants as fsConstants,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { access, mkdir, mkdtemp, readFile, rename, rm, stat, symlink, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { constants as osConstants, homedir, tmpdir } from "node:os";
import { delimiter, dirname, isAbsolute, join, resolve } from "node:path";
import process from "node:process";
import {
  isPersistentProjectOwnerMode,
  ownerChatHistoryPromptContext,
  planProjectOwnerSession,
  projectOwnerCodexArgs,
  projectOwnerCodexHome,
  projectOwnerSessionRegistryPath,
  recordProjectOwnerSession,
  requireProjectOwnerProjectId,
  requireWorkstateRuntimeRoot,
  resetProjectOwnerSession,
  resetProjectOwnerSessionMode,
  type ProjectOwnerSessionPlan,
} from "./project-owner-session.js";

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

type RoutingProject = {
  id: string;
  name: string;
  purpose: string;
  status: string;
};

type RuntimeProfile = {
  model: string;
  reasoning: "low" | "medium" | "high" | "xhigh";
};

type AgentUsage = {
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
  reasoning_output_tokens: number;
};

type RunTelemetry = {
  model: string;
  reasoning: RuntimeProfile["reasoning"];
  prompt_bytes: number;
  duration_ms: number;
  codex_pid: number;
};

type ProjectUnderstanding = {
  id: string;
  text: string;
  status: string;
};

type ProjectDecision = {
  id: string;
  text: string;
  rationale: string;
};

type CognitionPayload = {
  state: "uninitialized" | "draft" | "confirmed";
  version: number;
  sections: Array<{
    id: string;
    title: string;
    body: string;
    purpose: string;
    inclusionRules: string[];
    exclusionRules: string[];
    updateTriggers: string[];
    coverage: string[];
    order: number;
    sourceIDs: string[];
  }>;
  pendingRevisions: Array<{
    id: string;
    operation: string;
    status: string;
    baseVersion: number;
    touchedSectionIDs: string[];
    rationale: string;
    sourceIDs: string[];
  }>;
};

type OpenSemanticBundle = {
  id: string;
  threadID: string;
  projectId: string;
  disposition: "carry" | "commit";
  title: string;
  summary: string;
  evidenceCount: number;
  updatedAt: string;
};

type RuntimeRequest = {
  profile: RuntimeProfile;
} & (
  | {
      mode: "route";
      segment: Segment;
      projects: RoutingProject[];
      priorRoute?: { threadID: string; turnID: string; projectID: string; updatedAt: string };
      recentTurns: Segment[];
      openBundles: OpenSemanticBundle[];
    }
  | {
      mode: "batch_route";
      segments: Array<Pick<Segment, "id" | "threadID" | "turnID" | "cwd" | "userText" | "assistantText" | "timestamp">>;
      projects: RoutingProject[];
      routeHints: Array<{ threadID: string; projectID: string }>;
      recentTurns: Array<Pick<Segment, "id" | "threadID" | "turnID" | "cwd" | "userText" | "assistantText" | "timestamp">>;
      openBundles: OpenSemanticBundle[];
    }
  | {
      mode: "steward";
      segment: Segment;
      project: ProjectSummary & {
        cognition?: CognitionPayload | null;
        identity: { id: string; name: string; purpose: string; summary: string };
        topics: Array<{ id: string; title: string; summary: string; status: string; kind: string }>;
        activeWorklines: ProjectSummary["activeWorklines"];
        recentDeltas: Array<{ title: string; summary: string; kind: string; timestamp: string }>;
      };
    }
  | {
      mode: "batch_steward";
      segments: Segment[];
      project: ProjectSummary & {
        cognition?: CognitionPayload | null;
        identity: { id: string; name: string; purpose: string; summary: string };
        topics: Array<{ id: string; title: string; summary: string; status: string; kind: string }>;
        activeWorklines: ProjectSummary["activeWorklines"];
        recentDeltas: Array<{ title: string; summary: string; kind: string; timestamp: string }>;
      };
    }
  | {
      mode: "cognition_draft";
      project: {
        identity: { id: string; name: string; purpose: string; summary: string };
      };
      segments: Segment[];
    }
  | {
      mode: "rebuild";
      project: ProjectSummary & {
        currentUnderstanding: ProjectUnderstanding[];
        acceptedDecisions: ProjectDecision[];
        forbiddenDirections: string[];
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
        cognition?: CognitionPayload | null;
        identity: { id: string; name: string; purpose: string; summary: string };
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
      openBundles: OpenSemanticBundle[];
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
  | {
      mode: typeof resetProjectOwnerSessionMode;
      projectId: string;
    }
);

const routeSchema = {
  type: "object",
  properties: {
    action: { type: "string", enum: ["continue_previous", "select_project", "switch_project", "new_project", "ignore"] },
    projectId: { type: "string" },
    projectName: { type: "string" },
    projectSummary: { type: "string" },
    disposition: { type: "string", enum: ["ignore", "carry", "commit"] },
    bundleId: { type: "string" },
    bundleTitle: { type: "string" },
    bundleSummary: { type: "string" },
    signals: {
      type: "array",
      items: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: ["fact", "decision", "negation", "constraint", "topic", "delivery", "collaboration_rule"],
          },
          authority: {
            type: "string",
            enum: ["user_confirmed", "observed", "assistant_proposal", "inferred"],
          },
          summary: { type: "string" },
        },
        required: ["type", "authority", "summary"],
        additionalProperties: false,
      },
    },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    reason: { type: "string" },
  },
  required: [
    "action",
    "projectId",
    "projectName",
    "projectSummary",
    "disposition",
    "bundleId",
    "bundleTitle",
    "bundleSummary",
    "signals",
    "confidence",
    "reason",
  ],
  additionalProperties: false,
} as const;

function makeBatchRouteSchema(maximumPosition: number) {
  return {
    type: "object",
    properties: {
      routes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            startPosition: { type: "integer", minimum: 1, maximum: maximumPosition },
            endPosition: { type: "integer", minimum: 1, maximum: maximumPosition },
          action: {
            type: "string",
            enum: ["continue_previous", "select_project", "switch_project", "new_project", "ignore"],
          },
          projectId: { type: "string" },
          projectName: { type: "string" },
          projectSummary: { type: "string" },
          disposition: { type: "string", enum: ["ignore", "carry", "commit"] },
          bundleId: { type: "string" },
          bundleTitle: { type: "string" },
          bundleSummary: { type: "string" },
          signals: {
            type: "array",
            items: {
              type: "object",
              properties: {
                type: {
                  type: "string",
                  enum: ["fact", "decision", "negation", "constraint", "topic", "delivery", "collaboration_rule"],
                },
                authority: {
                  type: "string",
                  enum: ["user_confirmed", "observed", "assistant_proposal", "inferred"],
                },
                summary: { type: "string" },
              },
              required: ["type", "authority", "summary"],
              additionalProperties: false,
            },
          },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          reason: { type: "string" },
        },
          required: [
            "startPosition",
            "endPosition",
            "action",
            "projectId",
            "projectName",
            "projectSummary",
            "disposition",
            "bundleId",
            "bundleTitle",
            "bundleSummary",
            "signals",
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
}

const stewardContextPatchSchema = {
  type: "object",
  properties: {
    currentSummary: { type: "string" },
    revisionTitle: { type: "string" },
    revisionSummary: { type: "string" },
    revisionStatus: { type: "string", enum: ["observed", "confirmed"] },
    changes: { type: "array", items: { type: "string" } },
    understandingUpserts: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          text: { type: "string" },
          status: { type: "string", enum: ["observed", "inferred", "confirmed"] },
        },
        required: ["id", "text", "status"],
        additionalProperties: false,
      },
    },
    supersededUnderstandingIds: { type: "array", items: { type: "string" } },
    decisionUpserts: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          text: { type: "string" },
          rationale: { type: "string" },
        },
        required: ["id", "text", "rationale"],
        additionalProperties: false,
      },
    },
    supersededDecisionIds: { type: "array", items: { type: "string" } },
    forbiddenDirectionAdditions: { type: "array", items: { type: "string" } },
    forbiddenDirectionRemovals: { type: "array", items: { type: "string" } },
  },
  required: [
    "currentSummary",
    "revisionTitle",
    "revisionSummary",
    "revisionStatus",
    "changes",
    "understandingUpserts",
    "supersededUnderstandingIds",
    "decisionUpserts",
    "supersededDecisionIds",
    "forbiddenDirectionAdditions",
    "forbiddenDirectionRemovals",
  ],
  additionalProperties: false,
} as const;

const stewardTopicUpdateSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    title: { type: "string" },
    summary: { type: "string" },
    status: { type: "string", enum: ["captured", "discussing"] },
    kind: { type: "string", enum: ["product", "frontend", "backend"] },
    disposition: { type: "string", enum: ["futureDecision", "awaitingVerification"] },
    currentUnderstanding: { type: "string" },
    proposedDirection: { type: "string" },
    deferredReason: { type: "string" },
    revisitTrigger: { type: "string" },
    openQuestions: { type: "array", items: { type: "string" } },
  },
  required: [
    "id", "title", "summary", "status", "kind", "disposition",
    "currentUnderstanding", "proposedDirection", "deferredReason",
    "revisitTrigger", "openQuestions",
  ],
  additionalProperties: false,
} as const;

const cognitionProposalSectionSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    title: { type: "string" },
    body: { type: "string" },
    purpose: { type: "string" },
    inclusionRules: { type: "array", items: { type: "string" } },
    exclusionRules: { type: "array", items: { type: "string" } },
    updateTriggers: { type: "array", items: { type: "string" } },
    coverage: {
      type: "array",
      items: {
        type: "string",
        enum: ["projectPurpose", "currentUnderstanding", "decisionPrinciples", "currentState"],
      },
    },
    order: { type: "integer", minimum: 0 },
  },
  required: [
    "id", "title", "body", "purpose", "inclusionRules", "exclusionRules",
    "updateTriggers", "coverage", "order",
  ],
  additionalProperties: false,
} as const;

const cognitionProposalSchema = {
  type: "object",
  properties: {
    operation: { type: "string", enum: ["none", "update", "insert", "delete", "split", "merge"] },
    summary: { type: "string" },
    beforeSectionIDs: { type: "array", items: { type: "string" } },
    afterSections: { type: "array", items: cognitionProposalSectionSchema },
  },
  required: ["operation", "summary", "beforeSectionIDs", "afterSections"],
  additionalProperties: false,
} as const;

const timelineTurningPointSchema = {
  type: "object",
  properties: {
    scope: {
      type: "string",
      enum: [
        "none",
        "project",
        "module",
        "interaction",
        "informationArchitecture",
        "workline",
        "productModel",
      ],
    },
    title: { type: "string" },
    beforeMeaning: { type: "string" },
    afterMeaning: { type: "string" },
  },
  required: ["scope", "title", "beforeMeaning", "afterMeaning"],
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
    cognitionProposal: cognitionProposalSchema,
    turningPoint: timelineTurningPointSchema,
    topicUpdates: { type: "array", items: stewardTopicUpdateSchema },
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
    "cognitionProposal",
    "turningPoint",
    "topicUpdates",
  ],
  additionalProperties: false,
} as const;

const batchStewardSchema = {
  type: "object",
  properties: {
    changes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          evidenceIds: { type: "array", items: { type: "string" }, minItems: 1 },
          result: stewardSchema,
        },
        required: ["evidenceIds", "result"],
        additionalProperties: false,
      },
    },
  },
  required: ["changes"],
  additionalProperties: false,
} as const;

const cognitionDraftSectionSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    title: { type: "string" },
    body: { type: "string" },
    purpose: { type: "string" },
    inclusionRules: { type: "array", items: { type: "string" } },
    exclusionRules: { type: "array", items: { type: "string" } },
    updateTriggers: { type: "array", items: { type: "string" } },
    coverage: {
      type: "array",
      items: {
        type: "string",
        enum: ["projectPurpose", "currentUnderstanding", "decisionPrinciples", "currentState"],
      },
    },
    order: { type: "integer", minimum: 0 },
    sourceIDs: { type: "array", items: { type: "string" }, minItems: 1 },
  },
  required: [
    "id", "title", "body", "purpose", "inclusionRules", "exclusionRules",
    "updateTriggers", "coverage", "order", "sourceIDs",
  ],
  additionalProperties: false,
} as const;

const cognitionDraftSchema = {
  type: "object",
  properties: {
    isReady: { type: "boolean" },
    missingContext: { type: "array", items: { type: "string" } },
    sections: { type: "array", items: cognitionDraftSectionSchema },
  },
  required: ["isReady", "missingContext", "sections"],
  additionalProperties: false,
} as const;

const ownerChatSchema = {
  type: "object",
  properties: {
    reply: { type: "string" },
    cognitionProposal: cognitionProposalSchema,
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
  required: ["reply", "cognitionProposal", "topicUpdates"],
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
            enum: ["understanding", "objectModel", "decision", "forbiddenDirection", "topic", "worklineSignal", "delta", "supersession"],
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
    topics: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          summary: { type: "string" },
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
          evidenceIds,
        },
        required: [
          "id", "title", "summary", "kind", "disposition", "currentUnderstanding",
          "proposedDirection", "deferredReason", "revisitTrigger", "openQuestions",
          "evidenceIds",
        ],
        additionalProperties: false,
      },
    },
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
    "understanding", "acceptedDecisions", "forbiddenDirections", "topics", "worklines", "deltas",
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
  let totalBytes = 0;
  for await (const chunk of process.stdin) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    totalBytes += buffer.length;
    if (totalBytes > 2 * 1024 * 1024) {
      throw new Error("Agent request exceeded 2 MiB");
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function routePrompt(request: Extract<RuntimeRequest, { mode: "route" }>): string {
  return `You are Workstate's Portfolio Router and semantic gate. Read one completed Codex turn, including both the user message and the assistant's final result.

Your job is only to decide whether the turn matters durably, which project owns it, and which unresolved semantic bundle it advances. Do not inspect the filesystem, use tools, update project state, or classify project worklines.
One Codex task may switch projects between turns, but short or referential follow-ups usually continue the prior semantic scope. Route by actual meaning, not merely cwd.
Use continue_previous when the new turn continues, clarifies, corrects, or implements the prior routed work. Use select_project when there is no PRIOR ROUTE but the evidence belongs to an existing project. Use switch_project only when PRIOR ROUTE exists and the evidence positively establishes a different existing project. Use new_project when it establishes durable work that does not belong to any existing project. Use ignore only for casual, personal, or one-off content with no project consequence.
You own this decision. Choose the best semantic match from the evidence instead of asking the user to classify it. For continue_previous, projectId must equal PRIOR ROUTE.projectID. For select_project and switch_project, projectId must identify an exact existing project. If the chosen projectId already appears in PROJECTS, you MUST use continue_previous, select_project, or switch_project and MUST NOT use new_project. Use new_project only when no existing project semantically matches, and its projectId must not collide with any existing project id. For new_project, return a stable kebab-case projectId, a concise projectName, and a one-sentence projectSummary. Otherwise leave projectName and projectSummary empty.

Choose disposition independently from project routing:
- ignore: the whole completed turn has no durable consequence and contributes no necessary reasoning to an open bundle. Leave bundle fields and signals empty.
- carry: the turn contains relevant discussion, diagnosis, proposal, or partial execution, but the semantic result is not settled yet.
- commit: the turn establishes a durable fact, explicit decision, explicit negation, constraint, unresolved topic worth preserving, or an observed delivery/operational result.

Instructions are not automatically ignored. A command followed by an observed implementation, launch, commit, push, verification, or failure is durable evidence. An assistant proposal is never a confirmed decision. A later explicit user correction or rejection supersedes the earlier proposal.

The action and disposition must agree. ignore always means action=ignore, disposition=ignore, and empty project/bundle/signals. carry or commit always requires a non-ignore action, an existing or new project, and complete bundle fields. commit always requires at least one durable signal.

For carry or commit, attach the turn to exactly one semantic bundle. OPEN SEMANTIC BUNDLES include both unresolved carry bundles and committed bundles that have not yet been applied. Reuse an existing bundle id whenever the meaning continues, confirms, rejects, implements, verifies, or restates that subject; a commit does not close the bundle while it remains in this list. Create a new stable id prefixed with "bundle-" only for a genuinely different subject. Prefer reusing a plausible existing bundle over inventing near-duplicate names. bundleSummary is a concise complete replacement summary of the discussion so far, including unresolved alternatives and later corrections. Keep separate concurrently active subjects in separate bundles. The Project Owner, not you, will later read every original evidence turn in a committed bundle and make final project changes.

PROJECTS:
${JSON.stringify(request.projects)}

PRIOR ROUTE:
${JSON.stringify(request.priorRoute ?? null)}

RECENT TURNS IN THIS THREAD:
${JSON.stringify(request.recentTurns)}

OPEN SEMANTIC BUNDLES:
${JSON.stringify(request.openBundles)}

TURN:
${JSON.stringify(request.segment)}
`;
}

function batchRoutePrompt(request: Extract<RuntimeRequest, { mode: "batch_route" }>): string {
  return `You are Workstate's Portfolio Router. Distill and route one bounded batch from exactly one Codex conversation.

Return semantic route packets that partition ORDERED TURNS into chronological, contiguous spans. Each packet has inclusive startPosition and endPosition. The first packet must start at 1, each later packet must start exactly one position after the previous packet ends, and the final packet must end at ORDERED TURN COUNT. Merge adjacent turns when they jointly establish, revise, implement, verify, reject, or close the same semantic subject; keep independent subjects in separate packets. If a subject resumes after another subject interrupts it, create another span and reuse the same project and semantic bundle. Pure process turns may form an ignore span. Never include a RECENT TURN.
A single Codex task may change projects between packets. Use the ordered turns and RECENT TURNS in the same thread to resolve short follow-ups. A route hint is a strong prior for the current project, not a permanent lock. Explicit user scope statements override the hint.
Match projects by the subject being advanced and the supplied project purpose. Never choose a project merely because of the coding client, current working directory, document type, research/report vocabulary, or the fact that an Agent is doing the work. If the route hint no longer fits and no existing project purpose clearly matches the subject, use new_project instead of selecting a weakly related project.
Use continue_previous only when a prior turn in this batch or a route hint establishes that project. Use select_project when no prior route exists and the evidence belongs to an existing project. Use switch_project for a different existing project after a prior route exists. Use new_project only for durable work that fits none of the supplied projects, and reuse the same stable projectId when several turns establish the same new project. Use ignore only for content with no project consequence.
For each route, separately classify its semantic consequence:
- ignore: ordinary instructions, chatter, or intermediate process with no fact, decision, negation, constraint, durable topic, delivery result, or reasoning needed by a later turn;
- carry: relevant reasoning or an unresolved direction that has not become a durable project change yet;
- commit: a durable fact, explicit user decision or rejection, constraint, topic worth preserving, or observed implementation, verification, failure, commit, push, or delivery result.

An assistant proposal is not a user-confirmed decision. Later user corrections supersede earlier proposals. A command is not durable by itself, but its observed result can be. ignore requires action=ignore and empty project, bundle, and signals. carry and commit require a project and one concise semantic bundle. commit requires at least one signal. Reuse a matching OPEN SEMANTIC BUNDLE across batches, and reuse one bundle id within this batch when later turns continue, settle, reject, or verify the same subject; keep independent concurrent subjects separate. If a matching open bundle already has 80 or more evidence turns, commit it as an unresolved durable topic instead of extending it again.

Do not inspect files, use tools, expand project internals, or create worklines. The Project Owner will read the original turns for each routed project and decide the smallest durable mutation.

PROJECTS:
${JSON.stringify(request.projects)}

USER ROUTE HINTS:
${JSON.stringify(request.routeHints)}

RECENT TURNS IN THIS THREAD:
${JSON.stringify(request.recentTurns)}

OPEN SEMANTIC BUNDLES:
${JSON.stringify(request.openBundles)}

ORDERED TURN COUNT:
${request.segments.length}

ORDERED TURNS:
${JSON.stringify(request.segments.map((segment, index) => ({ position: index + 1, ...segment })))}
`;
}

function stewardPrompt(request: Extract<RuntimeRequest, { mode: "steward" }>): string {
  return `You are the Project Steward for exactly one project. Compare one completed Codex turn with the supplied Project HEAD.

Do not inspect the filesystem or use tools. Do not rewrite the whole project model. Return only the smallest durable state change.
Use no_change for chatter, planning with no accepted consequence, repeated information, and intermediate debugging.
Use ordinary_delta for objective implementation, verification, operational progress, and decisions explicitly made by the user in this turn.
Use ordinary_delta with topicUpdates when the evidence establishes durable unfinished work: a future direction not yet decided, or work whose result or acceptance still needs verification. Do not manufacture a workline for a topic.
When evidence corrects earlier project understanding, record the correction as an ordinary_delta. Do not ask the user to classify or reconfirm it.
Never infer userAccepted, integrated, rendered, or published without direct evidence in the turn.
Keep title short and summary to one sentence. Retain at most four facts.

Maintain project cognition separately from the event:
- Use cognitionProposal only for a material change to confirmed project cognition or its structure. Ordinary progress must return operation "none" with empty arrays and summary.
- Project cognition is the canonical current description of what the project is, why it exists, what its core objects mean, how they relate, and which user-confirmed principles and boundaries govern them. It is not a history, status recap, recommendation, or Owner strategy.
- Propose cognition changes only from an explicit user correction or a decision the user has clearly confirmed. Never create product direction, priority, risk, tradeoff, or next-step judgments on the user's behalf.
- A cognitionProposal is a proposal, not a fact. Return at most one for one semantic change.
- Copy exact existing section ids into beforeSectionIDs. Return complete replacement sections in afterSections.
- update is 1 -> 1 with the same id; insert is 0 -> 1+; delete is 1+ -> 0; split is 1 -> 2+; merge is 2+ -> 1.
- Preserve unaffected section wording, Markdown hierarchy, and Project Owner report voice. Do not rewrite the whole document for a local change.

Mark user-facing timeline turning points separately from project cognition:
- Use scope none with empty title and before/after meaning for ordinary progress, implementation detail, debugging, verification, acceptance, integration, or delivery-only changes.
- Mark a turning point only when this durable change alters how a human should understand the project, a module, an interaction, the information architecture, a workline's meaning, or the product model.
- Module- and interaction-level changes qualify when they materially replace an established model. Examples include changing an established split layout from top/bottom to left/right, or placing Storyboard inside the material-cognition system.
- Describe the prior meaning and the newly established meaning directly. Keep the marker concise and selective. Do not use it to claim rendered, accepted, integrated, or published state.
- This marker is maintained automatically by the Project Owner and does not require a user approval proposal.

Maintain unfinished topics separately:
- futureDecision means the user has not decided whether to proceed;
- awaitingVerification means work happened but its result, acceptance, or external feedback remains unknown;
- preserve and update a semantically matching supplied topic id instead of fragmenting it;
- a topic-only change uses worklineAction none and closureDisposition none. It may also update Project HEAD only when the same evidence explicitly establishes a durable constraint or decision.

You also own the project-internal workline lifecycle. A workline is a bounded stream with an independent purpose and completion condition, not a document section, product module, conversation, or individual turn.
- Use continue_existing when the turn advances an existing supplied workline.
- Use start_new when the turn clearly interrupts or diverges into an independently completable scope. A phrase such as "slightly interrupting" is only a signal; the semantic purpose and completion condition decide.
- Use complete_existing when this turn actually closes the bounded scope. Do not complete work merely because discussion paused.
- Use none only for no_change or a project-wide delta that genuinely belongs to no bounded workline.

The project has one explicit focused workline. Changing focus does not automatically mean parallel work.
- Set isParallel true only when the evidence shows the previous focused workline is still being actively advanced at the same time.
- Otherwise set isParallel false. Moving focus never completes, parks, or otherwise changes the previous workline's lifecycle.
- For complete_existing, set nextFocusedWorklineId to the different active workline that should become current, or empty when no focus change is needed.
- For continue_existing and start_new, nextFocusedWorklineId may equal worklineId when that workline is current after the change; otherwise leave it empty. It must never name a different workline.
- For none, leave nextFocusedWorklineId empty.

Whenever a workline ends, classify what remains:
- completed: its bounded result is settled and nothing needs later attention;
- awaiting_verification: implementation or action ended, but success, acceptance, external feedback, or a later result is still unknown;
- future_decision: the current execution ended, but a possible future direction still needs a decision;
- none: no workline ends in this decision.
Use a non-none closureDisposition only when complete_existing closes worklineId. A focus switch is not a closure. For awaiting_verification and future_decision, provide a concise carryoverTitle, carryoverSummary, and any carryoverQuestions. Leave carryover fields empty for none and completed.

Connected decisions under one purpose stay together. For example, display/highlight rules and folding rules are one workline when both are parts of confirming and optimizing the same material-graph interaction model. A separate data-mapping defect with its own diagnosis and fix is a different workline.

For continue_existing and complete_existing, worklineId must exactly match an id in ACTIVE WORKLINE IDS below. Any workline mentioned only in evidence or recent history is inactive and cannot be resumed. Use start_new for a new bounded round of work instead of reusing a parked, completed, abandoned, or unknown id. For start_new, return a stable project-prefixed kebab-case id, concise title and objective, plus branchFromWorklineId identifying the semantic parent scope; leave branchFromWorklineId empty only when branching from the project itself. Empty unused workline strings are required for none. Never reuse the broad parent workline merely because no narrower one exists.

ACTIVE WORKLINE IDS:
${JSON.stringify(request.project.activeWorklines.map((workline) => workline.id))}

PROJECT HEAD:
${JSON.stringify(request.project)}

NEW EVIDENCE:
${JSON.stringify(request.segment)}
`;
}

function batchStewardPrompt(request: Extract<RuntimeRequest, { mode: "batch_steward" }>): string {
  return `You are the Project Steward for exactly one project. Process every supplied completed Codex turn in chronological order while maintaining the evolving workline state.

The Portfolio Router has already assigned every supplied turn to this project. Do not reroute evidence or make project-ownership decisions. Return only project-internal semantic changes.

Return semantic project changes, not one decision per turn:
- omit chatter, repetition, intermediate debugging, and turns with no durable consequence;
- one change may cite several evidenceIds when those turns form one meaningful project change;
- separate changes only when they represent different durable state transitions;
- every evidenceId must be copied exactly from the supplied batch, and changes must remain chronological;
- every returned result uses ordinary_delta. An empty changes array is valid when the batch has no durable consequence;
- populate topicUpdates when a bundle resolves into durable unfinished work rather than a new workline;
- worklines are bounded streams with independent purposes and completion conditions, not pages, modules, conversations, or turns;
- continue the same workline when the purpose remains the same;
- start a new workline only for independently completable scope;
- complete a workline when its bounded deliverable closes, even when user acceptance remains separately unverified;
- changing focus is not parallel work. Set isParallel true only when evidence shows both scopes remain actively advancing;
- focus changes never complete, park, or otherwise mutate the previous workline; emit a separate complete_existing change only when evidence actually closes it;
- for complete_existing, nextFocusedWorklineId identifies a different active workline that becomes current, or is empty when no focus change is needed;
- for continue_existing and start_new, nextFocusedWorklineId may equal worklineId when that workline is current after the change, otherwise it is empty; it never names a different workline;
- for none, nextFocusedWorklineId is empty.
- closureDisposition is none unless worklineAction is complete_existing. It is completed for settled work, awaiting_verification when a result or acceptance is still unknown, and future_decision when later product choice remains.
- for awaiting_verification and future_decision, provide concise carryoverTitle, carryoverSummary, and carryoverQuestions; otherwise leave them empty.
- Use cognitionProposal only for a material change to the confirmed project cognition or its structure. Ordinary progress must return operation "none" with empty arrays and summary.
- Project cognition is the canonical current description of what the project is, why it exists, what its core objects mean, how they relate, and which user-confirmed principles and boundaries govern them. It is not a history, status recap, recommendation, or Owner strategy.
- Propose cognition changes only from an explicit user correction or a decision the user has clearly confirmed. Never create product direction, priority, risk, tradeoff, or next-step judgments on the user's behalf.
- Return at most one cognitionProposal for one semantic change in this whole batch. A proposal is not a fact and must not be phrased as already confirmed.
- Copy exact existing section ids into beforeSectionIDs and return complete replacement sections in afterSections. update is 1 -> 1, insert is 0 -> 1+, delete is 1+ -> 0, split is 1 -> 2+, and merge is 2+ -> 1. Preserve the existing Markdown hierarchy and Project Owner report voice.
- For every returned change, set turningPoint scope to none with empty text unless the change materially replaces a human-facing project, module, interaction, information-architecture, workline, or product-model meaning. Module-level changes count; routine implementation, debugging, verification, acceptance, integration, and delivery-only updates do not. A real turning point must contain a concise title plus direct beforeMeaning and afterMeaning, and it never claims delivery state.

Simulate the consequences of each earlier semantic change before deciding the next one. A later change may continue, complete, or switch away from a workline created earlier in this same batch. For continue_existing and complete_existing, use only an id in INITIAL ACTIVE WORKLINE IDS or an id created by an earlier start_new change in this output. Any workline mentioned only in evidence or recent history is inactive and cannot be resumed; start a new bounded workline instead. Use stable project-prefixed ids for new worklines. Do not inspect files or use tools. Never infer user acceptance, rendered behavior, integration, or publication without direct evidence.

INITIAL ACTIVE WORKLINE IDS:
${JSON.stringify(request.project.activeWorklines.map((workline) => workline.id))}

PROJECT HEAD:
${JSON.stringify(request.project)}

ORDERED NEW EVIDENCE:
${JSON.stringify(request.segments)}
`;
}

function cognitionDraftPrompt(request: Extract<RuntimeRequest, { mode: "cognition_draft" }>): string {
  return `You are the Project Knowledge Owner maintaining the first durable current-project document for exactly one project.

"Owner" means you own the accuracy, completeness, and continuity of project knowledge. The user alone owns product direction, priorities, tradeoffs, and final decisions. Do not make those decisions for the user.

Use only the supplied real conversation segments. Do not inspect files or use tools. Do not invent missing facts.
Return isReady=false with a non-empty missingContext array and an empty sections array when the evidence is insufficient.
Return isReady=true only when sections are non-empty and missingContext is empty.

Create the canonical current understanding of the project. A future user or Agent must be able to learn:
- what the project is and why it exists;
- which concepts, objects, or subsystems are central and what each one means;
- how those objects relate, where their responsibilities begin and end, and why the confirmed design is organized this way;
- which principles, constraints, and conclusions the user has confirmed;
- the project's current factual state, without replaying how it changed.

The document must contain only current valid conclusions. Omit superseded alternatives, abandoned explorations, conversation chronology, and the history of how understanding changed. Exclude unresolved ideas from the document. Use missingContext only when the evidence cannot establish the project's core identity or a coherent current model; otherwise leave unresolved material out for the topic system.

Report contract:
- Return 3 to 6 project-specific sections, not a generic checklist.
- The first section defines the project and its reason for existing. Give it a project-specific title.
- Organize the remaining sections around the project's real information model. Important objects must be explained through definition, responsibility, relationships, boundaries, and confirmed rationale. Do not substitute a module inventory for explanation.
- The visible section structure may vary by project. Keep hidden maintenance metadata specific enough that later updates can preserve the structure and change only the affected section.
- Write every body as clean, concise Markdown. Do not repeat the section title inside the body. Prefer short paragraphs and use bullets only when comparison or decomposition improves comprehension.
- State confirmed project knowledge directly. Do not add labels such as **Owner 判断**, **仍需验证**, or an executive recommendation.
- Never propose product direction, priorities, risks, tradeoffs, or next steps. Include a choice or rationale only when the evidence shows that the user already confirmed it.
- Never use the Chinese contrast template "不是……而是……". Avoid translationese, slogans, consultant language, and empty phrases such as "持续优化", "进一步完善", or "目前取得了一定进展".
- Do not narrate when individual conversations happened or describe a transition from an earlier model to the current one. Timeline and revision detail belong in project history.

The sections as a whole must cover:
- projectPurpose: why this project exists;
- currentUnderstanding: how the project should currently be understood;
- decisionPrinciples: principles that guide choices;
- currentState: what has been achieved and where it is now.
Every section must include a stable id, title, body, purpose, inclusionRules, exclusionRules, updateTriggers, coverage, order, and sourceIDs.
sourceIDs must copy only exact segment ids from the supplied evidence. Keep the document compact enough to reread, but complete enough for another Agent to understand the current project without asking the user to restate its concepts and confirmed rationale.

PROJECT IDENTITY:
${JSON.stringify(request.project.identity)}

REAL SOURCE SEGMENTS:
${JSON.stringify(request.segments)}
`;
}

function ownerChatPrompt(
  request: Extract<RuntimeRequest, { mode: "owner_chat" }>,
  historyContext: string,
): string {
  return `You are the Project Knowledge Owner for exactly one project. You own the accuracy and continuity of project knowledge. The user alone owns product direction, priorities, tradeoffs, and final decisions.

Talk with the user directly in natural, concise Chinese. Help them retrieve project knowledge, clarify concepts, organize unfinished topics and compare user-supplied alternatives. Use confirmed project cognition as durable memory and conversation history for continuity.

Do not choose a direction, assign priority, declare a risk, or recommend a next step unless the user explicitly asks for analysis. When analysis is requested, explain evidence and consequences without claiming decision authority. Identify contradictions and missing information instead of resolving them silently. Never use the Chinese contrast template "不是……而是……".

The user's new ideas, possible directions, future work, and unresolved product questions are NOT confirmed project facts. Discuss them and persist them as captured or discussing topics. Use futureDecision when the user has not decided whether to do something. Use awaitingVerification only when work already happened but its completion, result, acceptance, or external feedback remains unknown. Never label a new proposal as confirmed. Only the user-facing confirmation UI can promote a topic into the formal project flow; you cannot confirm decisions or create tasks.

When the user explicitly corrects project knowledge or confirms a conclusion that materially changes the current document, return one cognitionProposal using the tracked-change contract. It remains pending until the user accepts it in the document UI. Ordinary discussion returns operation "none" with empty arrays and summary. Copy exact existing section ids into beforeSectionIDs and return complete replacement sections in afterSections; use update 1 -> 1, insert 0 -> 1+, delete 1+ -> 0, split 1 -> 2+, or merge 2+ -> 1. Never silently rewrite the whole document. Preserve its Markdown hierarchy and current-project voice. Do not put discussion history, Owner recommendations, or unresolved ideas into project cognition.

Return topicUpdates when this turn creates durable unfinished work or materially changes an existing topic. Ordinary questions or chatter may return an empty array. Prefer updating ACTIVE TOPIC when supplied. Otherwise match an existing topic semantically before creating one. A single user turn should normally create at most one evolving topic: keep connected ideas together as one topic with multiple questions instead of fragmenting them. Split only when the user explicitly identifies independent backlog items. A correction must update the topic and append a userCorrection note. Use a stable kebab-case topicId for creation. Do not claim in reply that anything was approved, implemented, or scheduled.

PROJECT CONTEXT:
${JSON.stringify(request.project)}

UNSETTLED CODEX DISCUSSIONS:
${JSON.stringify(request.openBundles)}

${historyContext}

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
- explicit user decisions, prohibitions, and unresolved future-decision or verification topics;
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
- the durable object model, confirmed decisions, prohibited directions, and typed unfinished topics;
- a small set of semantic worklines, not one workline per conversation or implementation detail;
- only meaningful deltas that explain state transitions, decisions, implementation, verification, acceptance, integration, or publication.

Every object-model item, understanding item, decision, prohibited direction, topic, workline, and delta must reference one or more exact evidence ids from the corpus. Never invent an id. Every unfinished item must be a typed topic: futureDecision when the user has not decided whether to proceed, or awaitingVerification when work happened but its result or acceptance is still unknown. Keep display text clean: never embed citation syntax, evidence ids, timestamps, or source locators inside text fields; put ids only in evidenceIds. Use kebab-case ids prefixed with the project id. Use ISO-8601 timestamps copied from evidence. Active work must remain active even if earlier milestones completed. A discussion is not implementation, rendered behavior, user acceptance, integration, or publication.

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

const maximumCodexErrorBytes = 64 * 1024;
const moduleRequire = createRequire(import.meta.url);

type CodexExecutable = {
  path: string;
  pathDirectories: string[];
};

class CodexProcessError extends Error {
  constructor(
    message: string,
    readonly exitCode: number,
    readonly run: CodexProcessRun | null = null,
  ) {
    super(message);
    this.name = "CodexProcessError";
  }
}

async function executableFileExists(path: string): Promise<boolean> {
  try {
    const metadata = await stat(path);
    if (!metadata.isFile()) {
      return false;
    }
    await access(path, fsConstants.X_OK);
    return true;
  } catch {
    return false;
  }
}

async function readableFileExists(path: string): Promise<boolean> {
  try {
    const metadata = await stat(path);
    if (!metadata.isFile()) {
      return false;
    }
    await access(path, fsConstants.R_OK);
    return true;
  } catch {
    return false;
  }
}

async function initializeCodexHome(codexHome: string): Promise<void> {
  await mkdir(codexHome, { recursive: true, mode: 0o700 });
  const targetAuth = join(codexHome, "auth.json");
  if (await readableFileExists(targetAuth)) {
    return;
  }
  const sourceCodexHome = process.env.WORKSTATE_SOURCE_CODEX_HOME?.trim()
    || process.env.CODEX_HOME?.trim()
    || join(homedir(), ".codex");
  const sourceAuth = join(sourceCodexHome, "auth.json");
  if (!await readableFileExists(sourceAuth)) {
    throw new Error(`Codex authentication file is missing: ${sourceAuth}`);
  }
  try {
    await symlink(sourceAuth, targetAuth);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "EEXIST") {
      throw new Error(`Workstate Codex authentication file is not readable: ${targetAuth}`);
    }
    throw error;
  }
}

async function directoryExists(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}

async function bundledCodexExecutable(): Promise<CodexExecutable | null> {
  if (process.platform !== "darwin" || (process.arch !== "arm64" && process.arch !== "x64")) {
    return null;
  }

  const packageName = process.arch === "arm64"
    ? "@openai/codex-darwin-arm64"
    : "@openai/codex-darwin-x64";
  const targetTriple = process.arch === "arm64"
    ? "aarch64-apple-darwin"
    : "x86_64-apple-darwin";

  try {
    const codexPackagePath = moduleRequire.resolve("@openai/codex/package.json");
    const codexRequire = createRequire(codexPackagePath);
    const platformPackagePath = codexRequire.resolve(`${packageName}/package.json`);
    const vendorRoot = join(dirname(platformPackagePath), "vendor", targetTriple);
    const binaryPath = join(vendorRoot, "bin", "codex");
    if (!await executableFileExists(binaryPath)) {
      return null;
    }

    const codexPath = join(vendorRoot, "codex-path");
    return {
      path: binaryPath,
      pathDirectories: await directoryExists(codexPath) ? [codexPath] : [],
    };
  } catch {
    return null;
  }
}

async function codexExecutableOnPath(): Promise<CodexExecutable | null> {
  for (const pathEntry of (process.env.PATH ?? "").split(delimiter)) {
    if (!pathEntry) {
      continue;
    }
    const candidate = join(pathEntry, "codex");
    if (await executableFileExists(candidate)) {
      return { path: candidate, pathDirectories: [] };
    }
  }
  return null;
}

async function resolveCodexExecutable(): Promise<CodexExecutable> {
  const configuredPath = process.env.WORKSTATE_CODEX_BINARY?.trim();
  if (configuredPath) {
    const absolutePath = isAbsolute(configuredPath)
      ? configuredPath
      : resolve(process.cwd(), configuredPath);
    if (!await executableFileExists(absolutePath)) {
      throw new Error(`WORKSTATE_CODEX_BINARY is not an executable file: ${absolutePath}`);
    }
    return { path: absolutePath, pathDirectories: [] };
  }

  const bundled = await bundledCodexExecutable();
  if (bundled) {
    return bundled;
  }

  const pathExecutable = await codexExecutableOnPath();
  if (pathExecutable) {
    return pathExecutable;
  }

  throw new Error(
    "Unable to locate Codex CLI. Set WORKSTATE_CODEX_BINARY or install the bundled darwin Codex package.",
  );
}

function appendBoundedTail(current: Buffer, chunk: Buffer, maximumBytes: number): Buffer {
  if (chunk.length >= maximumBytes) {
    return Buffer.from(chunk.subarray(chunk.length - maximumBytes));
  }
  const overflow = current.length + chunk.length - maximumBytes;
  const retained = overflow > 0 ? current.subarray(overflow) : current;
  return Buffer.concat([retained, chunk], retained.length + chunk.length);
}

function exitCodeForSignal(signal: NodeJS.Signals): number {
  return 128 + (osConstants.signals[signal] ?? 0);
}

function processExists(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 1) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function signalProcessGroup(pid: number, signal: NodeJS.Signals): void {
  if (!Number.isInteger(pid) || pid <= 1) {
    return;
  }
  try {
    process.kill(-pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // The process already exited.
    }
  }
}

type AgentLease = {
  version: 1;
  parentPid: number;
  nodePid: number;
  codexPid: number;
  startedAt: string;
};

type AgentRuntimeLock = {
  version: 1;
  nodePid: number;
  parentPid: number;
  startedAt: string;
};

function agentRuntimeLockPath(): string | null {
  const runtimeRoot = process.env.WORKSTATE_RUNTIME_ROOT?.trim();
  return runtimeRoot ? join(runtimeRoot, "agent-runtime.lock") : null;
}

function acquireAgentRuntimeLock(): () => void {
  const path = agentRuntimeLockPath();
  if (!path) {
    return () => {};
  }
  mkdirSync(dirname(path), { recursive: true });
  const record: AgentRuntimeLock = {
    version: 1,
    nodePid: process.pid,
    parentPid: process.ppid,
    startedAt: new Date().toISOString(),
  };

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      writeFileSync(path, JSON.stringify(record), {
        encoding: "utf8",
        mode: 0o600,
        flag: "wx",
      });
      return () => {
        try {
          const current = JSON.parse(readFileSync(path, "utf8")) as Partial<AgentRuntimeLock>;
          if (current.nodePid === process.pid) {
            rmSync(path, { force: true });
          }
        } catch {
          // A missing lock already counts as released.
        }
      };
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== "EEXIST") {
        throw error;
      }
      let existing: Partial<AgentRuntimeLock> | null = null;
      try {
        existing = JSON.parse(readFileSync(path, "utf8")) as Partial<AgentRuntimeLock>;
      } catch {
        // Invalid stale lock data is removed below.
      }
      const startedAt = Date.parse(existing?.startedAt ?? "");
      const recent = Number.isFinite(startedAt)
        && Date.now() - startedAt < 30 * 60 * 1000;
      if (recent && processExists(existing?.nodePid ?? -1)) {
        throw new Error("Another Workstate Agent job is still active");
      }
      rmSync(path, { force: true });
    }
  }
  throw new Error("Could not acquire the Workstate Agent runtime lock");
}

function agentLeasePath(): string | null {
  const runtimeRoot = process.env.WORKSTATE_RUNTIME_ROOT?.trim();
  return runtimeRoot ? join(runtimeRoot, "agent-active-job.json") : null;
}

function removeAgentLease(): void {
  const path = agentLeasePath();
  if (!path) {
    return;
  }
  try {
    rmSync(path, { force: true });
  } catch {
    // Recovery on the next launch can remove it.
  }
}

function writeAgentLease(codexPid: number, parentPid: number): void {
  const path = agentLeasePath();
  if (!path) {
    return;
  }
  mkdirSync(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  const lease: AgentLease = {
    version: 1,
    parentPid,
    nodePid: process.pid,
    codexPid,
    startedAt: new Date().toISOString(),
  };
  writeFileSync(temporaryPath, JSON.stringify(lease), { encoding: "utf8", mode: 0o600 });
  renameSync(temporaryPath, path);
}

function cleanupStaleAgentLease(): void {
  const path = agentLeasePath();
  if (!path) {
    return;
  }
  try {
    const lease = JSON.parse(readFileSync(path, "utf8")) as Partial<AgentLease>;
    const startedAt = Date.parse(lease.startedAt ?? "");
    const recent = Number.isFinite(startedAt) && Date.now() - startedAt < 6 * 60 * 60 * 1000;
    const parentAlive = processExists(lease.parentPid ?? -1);
    const nodeAlive = processExists(lease.nodePid ?? -1);
    if (recent && parentAlive && nodeAlive) {
      throw new Error("Another Workstate Agent job is still active");
    }
    if (recent && (!parentAlive || !nodeAlive)) {
      signalProcessGroup(lease.codexPid ?? -1, "SIGTERM");
      if (!parentAlive && nodeAlive) {
        try {
          process.kill(lease.nodePid!, "SIGTERM");
        } catch {
          // The stale Node process already exited.
        }
      }
    }
  } catch {
    // Invalid or obsolete leases are removed below.
  }
  removeAgentLease();
}

type CodexProcessRun = {
  threadId: string;
  usage: AgentUsage;
  durationMs: number;
  codexPid: number;
};

type AgentUsageJournalRecord = {
  timestamp: string;
  mode: string;
  outcome: "succeeded" | "failed";
  usage: AgentUsage | null;
  telemetry: RunTelemetry;
  error: string;
};

function appendAgentUsageJournal(record: AgentUsageJournalRecord): void {
  const runtimeRoot = process.env.WORKSTATE_RUNTIME_ROOT?.trim();
  if (!runtimeRoot) {
    return;
  }
  mkdirSync(runtimeRoot, { recursive: true });
  const path = join(runtimeRoot, "agent-usage.jsonl");
  const previous = join(runtimeRoot, "agent-usage.previous.jsonl");
  try {
    if (statSync(path).size >= 2 * 1024 * 1024) {
      rmSync(previous, { force: true });
      renameSync(path, previous);
    }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      throw error;
    }
  }
  appendFileSync(path, `${JSON.stringify(record)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
}

async function runCodexProcess(
  executable: CodexExecutable,
  args: string[],
  prompt: string,
  codexHome: string,
): Promise<CodexProcessRun> {
  const environment = { ...process.env };
  environment.CODEX_HOME = codexHome;
  environment.HOME = dirname(codexHome);
  if (executable.pathDirectories.length > 0) {
    environment.PATH = [
      ...executable.pathDirectories,
      environment.PATH ?? "",
    ].filter(Boolean).join(delimiter);
  }

  return await new Promise<CodexProcessRun>((resolveRun, rejectRun) => {
    const startedAt = Date.now();
    const originalParentPid = process.ppid;
    const child = spawn(executable.path, args, {
      cwd: process.cwd(),
      env: environment,
      stdio: ["pipe", "pipe", "pipe"],
      detached: true,
    });
    const codexPid = child.pid ?? -1;
    let stderrTail: Buffer = Buffer.alloc(0);
    let stdoutErrorTail = "";
    let stdoutRemainder = "";
    let threadId = "";
    let usage: AgentUsage | null = null;
    let forwardedSignal: NodeJS.Signals | null = null;
    let inputError: Error | null = null;
    let outputError: Error | null = null;
    let settled = false;

    try {
      writeAgentLease(codexPid, originalParentPid);
    } catch (error) {
      signalProcessGroup(codexPid, "SIGTERM");
      rejectRun(error);
      return;
    }

    const forwardSignal = (signal: NodeJS.Signals): void => {
      forwardedSignal ??= signal;
      if (child.exitCode === null && child.signalCode === null) {
        signalProcessGroup(codexPid, signal);
      }
    };
    const handleSIGINT = (): void => forwardSignal("SIGINT");
    const handleSIGTERM = (): void => forwardSignal("SIGTERM");

    const cleanupListeners = (): void => {
      process.removeListener("SIGINT", handleSIGINT);
      process.removeListener("SIGTERM", handleSIGTERM);
      clearInterval(parentMonitor);
    };

    const finish = (error?: Error): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanupListeners();
      removeAgentLease();
      if (error) {
        const failedRun = usage
          ? {
            threadId,
            usage,
            durationMs: Date.now() - startedAt,
            codexPid,
          }
          : null;
        if (error instanceof CodexProcessError) {
          rejectRun(new CodexProcessError(error.message, error.exitCode, failedRun));
        } else {
          rejectRun(new CodexProcessError(error.message, 1, failedRun));
        }
      } else {
        if (!usage) {
          rejectRun(new Error("Codex CLI completed without token usage"));
          return;
        }
        resolveRun({
          threadId,
          usage,
          durationMs: Date.now() - startedAt,
          codexPid,
        });
      }
    };

    const consumeEventLine = (line: string): void => {
      if (!line.trim()) {
        return;
      }
      let event: unknown;
      try {
        event = JSON.parse(line);
      } catch {
        throw new Error("Codex CLI emitted invalid JSONL output");
      }
      if (!event || typeof event !== "object") {
        return;
      }
      const value = event as {
        type?: unknown;
        thread_id?: unknown;
        usage?: Partial<AgentUsage>;
        message?: unknown;
        error?: unknown;
      };
      if (value.type === "error" || value.type === "turn.failed") {
        const detail = typeof value.message === "string"
          ? value.message
          : value.error === undefined
            ? JSON.stringify(event)
            : typeof value.error === "string"
              ? value.error
              : JSON.stringify(value.error);
        stdoutErrorTail = detail.slice(-maximumCodexErrorBytes);
      }
      if (value.type === "thread.started" && typeof value.thread_id === "string") {
        threadId = value.thread_id;
      }
      if (value.type === "turn.completed" && value.usage) {
        const candidate = value.usage;
        const fields = [
          candidate.input_tokens,
          candidate.cached_input_tokens,
          candidate.output_tokens,
          candidate.reasoning_output_tokens,
        ];
        if (!fields.every((field) => Number.isInteger(field) && (field ?? -1) >= 0)) {
          throw new Error("Codex CLI returned invalid token usage");
        }
        usage = candidate as AgentUsage;
      }
    };

    const consumeStdout = (data: Buffer | string): void => {
      stdoutRemainder += Buffer.isBuffer(data) ? data.toString("utf8") : data;
      if (Buffer.byteLength(stdoutRemainder, "utf8") > 1024 * 1024) {
        throw new Error("Codex CLI JSONL line exceeded 1 MiB");
      }
      while (true) {
        const newline = stdoutRemainder.indexOf("\n");
        if (newline < 0) {
          return;
        }
        const line = stdoutRemainder.slice(0, newline);
        stdoutRemainder = stdoutRemainder.slice(newline + 1);
        consumeEventLine(line);
      }
    };

    const parentMonitor = setInterval(() => {
      if (process.ppid !== originalParentPid || !processExists(originalParentPid)) {
        forwardSignal("SIGTERM");
        setTimeout(() => signalProcessGroup(codexPid, "SIGKILL"), 2_000).unref();
      }
    }, 1_000);
    parentMonitor.unref();

    process.once("SIGINT", handleSIGINT);
    process.once("SIGTERM", handleSIGTERM);
    child.stdout.on("data", (data: Buffer | string) => {
      if (outputError) {
        return;
      }
      try {
        consumeStdout(data);
      } catch (error) {
        outputError = error instanceof Error ? error : new Error(String(error));
        signalProcessGroup(codexPid, "SIGTERM");
      }
    });
    child.stderr.on("data", (data: Buffer | string) => {
      const chunk = Buffer.isBuffer(data) ? data : Buffer.from(data);
      stderrTail = appendBoundedTail(stderrTail, chunk, maximumCodexErrorBytes);
    });
    child.stdin.on("error", (error: NodeJS.ErrnoException) => {
      if (error.code !== "EPIPE") {
        inputError = error;
        child.kill("SIGTERM");
      }
    });
    child.once("error", (error) => finish(error));
    child.once("close", (code, signal) => {
      if (settled) {
        return;
      }

      if (inputError) {
        finish(inputError);
        return;
      }

      if (!outputError && stdoutRemainder.trim()) {
        try {
          consumeEventLine(stdoutRemainder);
          stdoutRemainder = "";
        } catch (error) {
          outputError = error instanceof Error ? error : new Error(String(error));
        }
      }
      if (outputError) {
        finish(outputError);
        return;
      }

      const stderr = stderrTail.toString("utf8").trim();
      const processError = stderr || stdoutErrorTail.trim();
      if (forwardedSignal) {
        finish(new CodexProcessError(
          `Codex CLI was terminated by ${forwardedSignal}${processError ? `: ${processError}` : ""}`,
          exitCodeForSignal(forwardedSignal),
        ));
        return;
      }
      if (signal) {
        finish(new CodexProcessError(
          `Codex CLI exited from signal ${signal}${processError ? `: ${processError}` : ""}`,
          exitCodeForSignal(signal),
        ));
        return;
      }
      if (code !== 0) {
        finish(new CodexProcessError(
          `Codex CLI exited with code ${code ?? 1}${processError ? `: ${processError}` : ""}`,
          code ?? 1,
        ));
        return;
      }
      finish();
    });

    child.stdin.end(prompt, "utf8");
  });
}

async function runCodexWithHome(
  prompt: string,
  outputSchema: unknown,
  profile: RuntimeProfile,
  mode: string,
  codexHome: string,
  argsFor: (schemaPath: string, responsePath: string) => string[],
  fallbackRunId: string,
): Promise<{
  runId: string;
  result: unknown;
  usage: AgentUsage;
  telemetry: RunTelemetry;
}> {
  const executable = await resolveCodexExecutable();
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "workstate-codex-"));
  const schemaPath = join(temporaryDirectory, "output-schema.json");
  const responsePath = join(temporaryDirectory, "final-response.json");
  let invocationFailed = false;
  let processRun: CodexProcessRun | null = null;
  const invocationStartedAt = Date.now();

  try {
    await writeFile(schemaPath, JSON.stringify(outputSchema), { encoding: "utf8", mode: 0o600 });
    processRun = await runCodexProcess(executable, argsFor(schemaPath, responsePath), prompt, codexHome);

    const responseStats = await stat(responsePath);
    if (responseStats.size > 8 * 1024 * 1024) {
      throw new Error("Codex final response exceeded 8 MiB");
    }
    const finalResponse = await readFile(responsePath, "utf8");
    if (!finalResponse.trim()) {
      throw new Error("Codex CLI completed without a final response");
    }
    const telemetry: RunTelemetry = {
      model: profile.model,
      reasoning: profile.reasoning,
      prompt_bytes: Buffer.byteLength(prompt, "utf8"),
      duration_ms: processRun.durationMs,
      codex_pid: processRun.codexPid,
    };
    return {
      runId: processRun.threadId || fallbackRunId,
      result: JSON.parse(finalResponse) as unknown,
      usage: processRun.usage,
      telemetry,
    };
  } catch (error) {
    invocationFailed = true;
    const failedRun = processRun
      ?? (error instanceof CodexProcessError ? error.run : null);
    const message = error instanceof Error ? error.message : String(error);
    try {
      appendAgentUsageJournal({
        timestamp: new Date().toISOString(),
        mode,
        outcome: "failed",
        usage: failedRun?.usage ?? null,
        telemetry: {
          model: profile.model,
          reasoning: profile.reasoning,
          prompt_bytes: Buffer.byteLength(prompt, "utf8"),
          duration_ms: failedRun?.durationMs ?? Date.now() - invocationStartedAt,
          codex_pid: failedRun?.codexPid ?? -1,
        },
        error: message.slice(0, 500),
      });
    } catch (journalError) {
      const journalMessage = journalError instanceof Error
        ? journalError.message
        : String(journalError);
      throw new Error(`${message}; failed to write Agent usage journal: ${journalMessage}`);
    }
    throw error;
  } finally {
    try {
      await rm(temporaryDirectory, { recursive: true, force: true });
    } catch (cleanupError) {
      if (!invocationFailed) {
        const message = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
        throw new Error(`Failed to remove Codex temporary directory: ${message}`);
      }
    }
  }
}

async function runEphemeralCodex(
  prompt: string,
  outputSchema: unknown,
  profile: RuntimeProfile,
  mode: string,
): Promise<{
  runId: string;
  result: unknown;
  usage: AgentUsage;
  telemetry: RunTelemetry;
}> {
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "workstate-codex-"));
  const isolatedCodexHome = join(temporaryDirectory, "codex-home");
  let completed = false;
  try {
    await initializeCodexHome(isolatedCodexHome);
    const run = await runCodexWithHome(
      prompt,
      outputSchema,
      profile,
      mode,
      isolatedCodexHome,
      (schemaPath, responsePath) => [
        "exec",
        "--ephemeral",
        "--ignore-user-config",
        "--ignore-rules",
        "--sandbox", "read-only",
        "--cd", process.cwd(),
        "--skip-git-repo-check",
        "--model", profile.model,
        "--config", "approval_policy=\"never\"",
        "--config", `model_reasoning_effort="${profile.reasoning}"`,
        "--config", "sandbox_workspace_write.network_access=false",
        "--config", "web_search=\"disabled\"",
        "--output-schema", schemaPath,
        "--output-last-message", responsePath,
        "--color", "never",
        "--json",
        "-",
      ],
      `ephemeral-run-${randomUUID().toLowerCase()}`,
    );
    completed = true;
    return run;
  } finally {
    try {
      await rm(temporaryDirectory, { recursive: true, force: true });
    } catch (cleanupError) {
      if (completed) {
        const message = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
        throw new Error(`Failed to remove Codex temporary directory: ${message}`);
      }
    }
  }
}

type PersistentProjectOwnerSession = {
  projectId: string;
  registryPath: string;
  codexHome: string;
  plan: ProjectOwnerSessionPlan;
};

async function runPersistentProjectOwnerCodex(
  prompt: string,
  outputSchema: unknown,
  profile: RuntimeProfile,
  mode: string,
  session: PersistentProjectOwnerSession,
): Promise<{
  runId: string;
  result: unknown;
  usage: AgentUsage;
  telemetry: RunTelemetry;
}> {
  await initializeCodexHome(session.codexHome);
  try {
    const run = await runCodexWithHome(
      prompt,
      outputSchema,
      profile,
      mode,
      session.codexHome,
      (schemaPath, responsePath) => projectOwnerCodexArgs({
        plan: session.plan,
        schemaPath,
        responsePath,
        model: profile.model,
        reasoning: profile.reasoning,
        cwd: process.cwd(),
      }),
      session.plan.kind === "resume" ? session.plan.threadId : "",
    );
    if (session.plan.kind === "resume") {
      if (run.runId !== session.plan.threadId) {
        throw new Error(
          `Codex resumed a different thread (${run.runId || "none"}) than the stored thread ${session.plan.threadId}`,
        );
      }
      return run;
    }
    await recordProjectOwnerSession(session.registryPath, session.projectId, run.runId);
    return run;
  } catch (error) {
    if (session.plan.kind !== "resume") {
      throw error;
    }
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Project Owner Codex session resume failed for project ${session.projectId} (thread ${session.plan.threadId}). `
      + `The registry entry was preserved and no fresh session was started. `
      + `After diagnosing the stored session as stale or corrupt, send mode ${resetProjectOwnerSessionMode} with this projectId, then retry. `
      + `Resume detail: ${detail}`,
    );
  }
}

function projectIdForPersistentOwnerRequest(request: RuntimeRequest): string {
  switch (request.mode) {
    case "cognition_draft":
      return requireProjectOwnerProjectId(request.project.identity.id);
    case "steward":
    case "batch_steward":
    case "owner_chat":
      return requireProjectOwnerProjectId(request.project.id);
    default:
      throw new Error(`Mode ${request.mode} does not use a persistent Project Owner session`);
  }
}

async function main(): Promise<void> {
  cleanupStaleAgentLease();
  const request = await readRequest();
  if (request.mode === resetProjectOwnerSessionMode) {
    const runtimeRoot = requireWorkstateRuntimeRoot(process.env.WORKSTATE_RUNTIME_ROOT);
    const result = await resetProjectOwnerSession(projectOwnerSessionRegistryPath(runtimeRoot), request.projectId);
    process.stdout.write(
      JSON.stringify({
        mode: request.mode,
        runtimeThreadId: result.removedThreadId ?? "",
        usage: null,
        telemetry: null,
        result,
      }),
    );
    return;
  }
  let persistentSession: PersistentProjectOwnerSession | null = null;
  if (isPersistentProjectOwnerMode(request.mode)) {
    const runtimeRoot = requireWorkstateRuntimeRoot(process.env.WORKSTATE_RUNTIME_ROOT);
    const projectId = projectIdForPersistentOwnerRequest(request);
    const registryPath = projectOwnerSessionRegistryPath(runtimeRoot);
    persistentSession = {
      projectId,
      registryPath,
      codexHome: projectOwnerCodexHome(runtimeRoot),
      plan: await planProjectOwnerSession(registryPath, projectId),
    };
  }
  let distilledCorpus: string | undefined;
  if (request.mode === "rebuild") {
    const evidenceStats = await stat(request.evidencePath);
    if (evidenceStats.size > 16 * 1024 * 1024) {
      throw new Error("Distilled rebuild evidence exceeded 16 MiB");
    }
    distilledCorpus = await readFile(request.evidencePath, "utf8");
  }
  const prompt = request.mode === "route"
    ? routePrompt(request)
    : request.mode === "batch_route"
      ? batchRoutePrompt(request)
    : request.mode === "steward"
      ? stewardPrompt(request)
    : request.mode === "batch_steward"
      ? batchStewardPrompt(request)
      : request.mode === "cognition_draft"
        ? cognitionDraftPrompt(request)
      : request.mode === "collaboration_steward"
        ? collaborationStewardPrompt(request)
      : request.mode === "global_chat_route"
        ? globalChatRoutePrompt(request)
      : request.mode === "owner_chat"
        ? ownerChatPrompt(
          request,
          ownerChatHistoryPromptContext(persistentSession!.plan, request.history),
        )
      : request.mode === "brief"
        ? briefPrompt(request)
      : request.mode === "distill"
        ? distillPrompt(request)
        : rebuildPrompt(request, distilledCorpus!);
  const outputSchema = request.mode === "route"
    ? routeSchema
    : request.mode === "batch_route"
      ? makeBatchRouteSchema(request.segments.length)
    : request.mode === "steward"
      ? stewardSchema
    : request.mode === "batch_steward"
      ? batchStewardSchema
      : request.mode === "cognition_draft"
        ? cognitionDraftSchema
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
  const run = persistentSession
    ? await runPersistentProjectOwnerCodex(
      prompt,
      outputSchema,
      request.profile,
      request.mode,
      persistentSession,
    )
    : await runEphemeralCodex(prompt, outputSchema, request.profile, request.mode);
  try {
    let result = run.result;
    if (request.mode === "batch_route") {
      if (!result || typeof result !== "object" || !Array.isArray((result as { routes?: unknown }).routes)) {
        throw new Error("Batch Router result does not contain an ordered routes array");
      }
      const routes = (result as { routes: unknown[] }).routes;
      let nextPosition = 1;
      routes.forEach((route, index) => {
        if (!route || typeof route !== "object" || Array.isArray(route)) {
          throw new Error(`Batch Router packet ${index} is not an object`);
        }
        const startPosition = (route as { startPosition?: unknown }).startPosition;
        const endPosition = (route as { endPosition?: unknown }).endPosition;
        if (!Number.isInteger(startPosition) || !Number.isInteger(endPosition)) {
          throw new Error(`Batch Router packet ${index} has invalid evidence bounds`);
        }
        if (startPosition !== nextPosition || (endPosition as number) < (startPosition as number)) {
          throw new Error(`Batch Router packet ${index} does not continue the ordered partition`);
        }
        nextPosition = (endPosition as number) + 1;
      });
      if (nextPosition !== request.segments.length + 1) {
        throw new Error(
          `Batch Router partition ends at ${nextPosition - 1} of ${request.segments.length} ordered turns`,
        );
      }
    }
    appendAgentUsageJournal({
      timestamp: new Date().toISOString(),
      mode: request.mode,
      outcome: "succeeded",
      usage: run.usage,
      telemetry: run.telemetry,
      error: "",
    });
    process.stdout.write(
      JSON.stringify({
        mode: request.mode,
        runtimeThreadId: run.runId,
        usage: run.usage,
        telemetry: run.telemetry,
        result,
      }),
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    appendAgentUsageJournal({
      timestamp: new Date().toISOString(),
      mode: request.mode,
      outcome: "failed",
      usage: run.usage,
      telemetry: run.telemetry,
      error: message.slice(0, 500),
    });
    throw error;
  }
}

async function runMainWithLock(): Promise<void> {
  const release = acquireAgentRuntimeLock();
  try {
    await main();
  } finally {
    release();
  }
}

runMainWithLock().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = error instanceof CodexProcessError ? error.exitCode : 1;
});
