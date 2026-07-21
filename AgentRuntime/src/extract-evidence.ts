import { createReadStream, createWriteStream } from "node:fs";
import { once } from "node:events";
import { createInterface } from "node:readline";

type Cursor = {
  threadID: string;
  cwd: string;
  activeTurnID: string;
  userMessages: string[];
};

async function main(): Promise<void> {
  const outputPath = process.argv[2];
  const inputs = process.argv.slice(3);
  if (!outputPath || inputs.length === 0) {
    throw new Error("Usage: extract-evidence OUTPUT.jsonl INPUT.jsonl [...]");
  }

  const output = createWriteStream(outputPath, { encoding: "utf8" });
  for (const inputPath of inputs) {
    await extract(inputPath, output);
  }
  output.end();
  await once(output, "finish");
}

async function extract(inputPath: string, output: NodeJS.WritableStream): Promise<void> {
  const cursor: Cursor = { threadID: "", cwd: "", activeTurnID: "", userMessages: [] };
  const lines = createInterface({ input: createReadStream(inputPath), crlfDelay: Infinity });

  for await (const line of lines) {
    let record: any;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }
    const payload = record?.payload;
    if (!payload || typeof payload !== "object") continue;

    if (record.type === "session_meta") {
      cursor.threadID = payload.id ?? payload.session_id ?? cursor.threadID;
      cursor.cwd = payload.cwd ?? cursor.cwd;
      continue;
    }
    if (record.type === "turn_context") {
      cursor.cwd = payload.cwd ?? cursor.cwd;
      cursor.activeTurnID = payload.turn_id ?? cursor.activeTurnID;
      continue;
    }
    if (record.type !== "event_msg") continue;

    if (payload.type === "task_started") {
      cursor.activeTurnID = payload.turn_id ?? "";
      cursor.userMessages = [];
    } else if (payload.type === "user_message") {
      const message = String(payload.message ?? "").trim();
      if (message) cursor.userMessages.push(message);
    } else if (payload.type === "task_complete") {
      const turnID = String(payload.turn_id ?? cursor.activeTurnID);
      const assistantText = String(payload.last_agent_message ?? "").trim();
      const userText = cursor.userMessages.join("\n\n").trim();
      if (cursor.threadID && turnID && userText && assistantText) {
        output.write(`${JSON.stringify({
          id: `${cursor.threadID}:${turnID}`,
          threadID: cursor.threadID,
          turnID,
          sourcePath: inputPath,
          startOffset: 0,
          endOffset: 0,
          cwd: cursor.cwd,
          userText,
          assistantText,
          timestamp: record.timestamp,
        })}\n`);
      }
      cursor.activeTurnID = "";
      cursor.userMessages = [];
    }
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
