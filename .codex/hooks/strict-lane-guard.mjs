#!/usr/bin/env node

import fs from "node:fs";

function readInput() {
  try {
    const raw = fs.readFileSync(0, "utf8").trim();
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function deny(eventName, message) {
  if (eventName === "PreToolUse") {
    console.log(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: message
      }
    }));
    process.exit(0);
  }

  console.error(message);
  process.exit(2);
}

function addContext(eventName, message) {
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: eventName,
      additionalContext: message
    }
  }));
}

function getCommand(input) {
  const toolInput = input.tool_input ?? {};
  return String(toolInput.command ?? "");
}

function normalize(text) {
  return text.replace(/\\/g, "/").toLowerCase();
}

function changedPathsFromPatch(patch) {
  const paths = [];
  for (const line of patch.split(/\r?\n/)) {
    const match = line.match(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/);
    if (match) paths.push(match[1].trim());
  }
  return paths;
}

function containsSecretMaterial(text) {
  const patterns = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/i,
    /\bghp_[A-Za-z0-9_]{20,}\b/,
    /\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
    /\bsk-[A-Za-z0-9_-]{20,}\b/,
    /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/,
    /\b(service_role|anon|access|refresh|secret|token|password)\s*[:=]\s*['"][^'"]{12,}['"]/i
  ];
  return patterns.some((pattern) => pattern.test(text));
}

function shellGuard(command, eventName) {
  const cmd = normalize(command);

  const blocks = [
    {
      pattern: /\bgit\s+add\s+(?:\.|-a|--all)(?:\s|$)/,
      reason: "Blocked broad git add. Stage explicit allowed files only; tmp/** and .env* must never be swept in."
    },
    {
      pattern: /\bgit\s+commit\b[^&|;\n]*\s-a\b/,
      reason: "Blocked git commit -a. Stage explicit allowed files and inspect diff first."
    },
    {
      pattern: /\bgit\s+add\b[^&|;\n]*(^|\s)(tmp\/|\.env|supabase\/\.temp)/,
      reason: "Blocked staging tmp/**, .env*, or supabase/.temp/**."
    },
    {
      pattern: /\bgit\s+push\s+origin\s+main\b/,
      reason: "Blocked push to main. main maps to production and requires separate release confirmation."
    },
    {
      pattern: /\bgh\s+pr\s+merge\b/,
      reason: "Blocked gh pr merge. PR merge requires separate explicit user confirmation."
    },
    {
      pattern: /\bvercel\b[^&|;\n]*(--prod|deploy|rollback|env\s+(add|rm|remove))/,
      reason: "Blocked Vercel write/production operation. Vercel changes require Strict Lane confirmation."
    },
    {
      pattern: /\bsupabase\s+(db\s+(push|reset)|migration\s+up|functions\s+deploy|link)\b/,
      reason: "Blocked direct Supabase write/link command. Use approved dev-safe npm scripts or get Strict Lane confirmation."
    },
    {
      pattern: /\bfopyjewbsvusftpqbtml\b/,
      reason: "Blocked production Supabase project ref in a command. Production database work requires separate confirmation."
    },
    {
      pattern: /\b(remove-item|rm|del)\b[^&|;\n]*(tmp\/|\.env|supabase\/\.temp)/,
      reason: "Blocked destructive command touching protected local state. Inspect and clean manually with explicit scope."
    }
  ];

  for (const block of blocks) {
    if (block.pattern.test(cmd)) {
      deny(eventName, block.reason);
    }
  }

  const reminders = [];
  if (/\b(main|production|prod|release|hotfix)\b/.test(cmd)) {
    reminders.push("main/production/release work is Strict Lane.");
  }
  if (/\b(database|supabase|migration|rls|rpc|psql)\b/.test(cmd)) {
    reminders.push("database/Supabase/migration work requires project ref, dev validation, and rollback.");
  }
  if (reminders.length > 0) {
    addContext(eventName, `Nikki boundary reminder: ${reminders.join(" ")}`);
  }
}

function patchGuard(patch, eventName) {
  const paths = changedPathsFromPatch(patch).map(normalize);
  const blockedPath = paths.find((path) =>
    path === ".env" ||
    path.startsWith(".env.") ||
    path.startsWith("tmp/") ||
    path.startsWith("supabase/.temp/")
  );

  if (blockedPath) {
    deny(eventName, `Blocked edit to protected path: ${blockedPath}. Do not commit tmp/**, .env*, or supabase/.temp/**.`);
  }

  if (containsSecretMaterial(patch)) {
    deny(eventName, "Blocked patch that appears to contain secret material.");
  }

  const reminders = [];
  if (paths.includes("docs/ai/rules.md")) {
    reminders.push("docs/ai/RULES.md is Strict Lane and needs explicit authorization.");
  }
  if (paths.some((path) => path.startsWith("supabase/") || path.includes("migration"))) {
    reminders.push("database/migration edits require database governance checks.");
  }
  if (paths.some((path) => path === "package.json" || path === "package-lock.json" || path === "vite.config.js")) {
    reminders.push("config/build edits are config risk and should not be mixed into docs-only work.");
  }
  if (reminders.length > 0) {
    addContext(eventName, `Nikki edit reminder: ${reminders.join(" ")}`);
  }
}

const input = readInput();
const eventName = input.hook_event_name ?? "";

if (eventName === "PreToolUse") {
  if (input.tool_name === "Bash") shellGuard(getCommand(input), eventName);
  if (input.tool_name === "apply_patch") patchGuard(getCommand(input), eventName);
}
