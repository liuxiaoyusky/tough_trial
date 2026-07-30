#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const repositoryRoot = new URL("../", import.meta.url);
const excludedFiles = new Set([
  "Tools/check-sensitive-info.mjs",
  "Tools/release-preflight.sh",
]);
const rules = [
  {
    name: "concrete Feishu Base URL",
    pattern: /https?:\/\/[^\s"'<>]+\.feishu\.cn\/base\/[A-Za-z0-9]+/i,
  },
  {
    name: "private macOS home path",
    pattern: /\/Users\/(?!Shared(?:\/|$))[^/\s]+(?:\/|$)/i,
  },
  {
    name: "assigned credential value",
    pattern:
      /(?:api[_-]?key|client[_-]?secret|app[_-]?secret|access[_-]?token|refresh[_-]?token)\s*[:=]\s*["']([A-Za-z0-9_./+=-]{8,})["']/i,
    allow: (match) =>
      /(?:fake|test|example|placeholder|never-sent)/i.test(match[1]),
  },
  {
    name: "OpenAI-style API key",
    pattern: /\bsk-[A-Za-z0-9_-]{20,}\b/,
  },
  {
    name: "GitHub token",
    pattern: /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
  },
  {
    name: "Feishu application identifier",
    pattern: /\bcli_[A-Za-z0-9]{16,}\b/,
  },
  {
    name: "Bearer credential",
    pattern: /\bAuthorization\s*:\s*Bearer\s+([A-Za-z0-9_./+=-]{12,})/i,
    allow: (match) =>
      /(?:fake|test|example|placeholder|never-sent)/i.test(match[1]),
  },
  {
    name: "private key material",
    pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  },
];
const localDenylistPath = new URL(
  "sensitive-patterns.local.txt",
  repositoryRoot,
);
const localDenylist = existsSync(localDenylistPath)
  ? readFileSync(localDenylistPath, "utf8")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#"))
  : [];

const output = execFileSync(
  "git",
  ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
  { cwd: repositoryRoot, encoding: "utf8" },
);
const violations = [];

for (const relativePath of output.split("\0").filter(Boolean)) {
  if (excludedFiles.has(relativePath)) continue;

  let contents;
  try {
    contents = readFileSync(new URL(relativePath, repositoryRoot));
  } catch {
    continue;
  }
  if (contents.includes(0)) continue;

  const text = contents.toString("utf8");
  for (const rule of rules) {
    const match = text.match(rule.pattern);
    if (match && !rule.allow?.(match)) {
      violations.push({ relativePath, rule: rule.name });
    }
  }
  for (const marker of localDenylist) {
    if (text.includes(marker)) {
      violations.push({
        relativePath,
        rule: "local denylist marker",
      });
    }
  }
}

if (violations.length > 0) {
  process.stderr.write("Sensitive information check failed:\n");
  for (const violation of violations) {
    process.stderr.write(`- ${violation.relativePath}: ${violation.rule}\n`);
  }
  process.exitCode = 1;
} else {
  process.stdout.write("Sensitive information check passed.\n");
}
