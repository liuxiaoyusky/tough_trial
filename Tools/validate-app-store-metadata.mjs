#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const metadataPath =
  process.argv[2] ?? "docs/release/app-store-metadata.zh-Hans.json";
const metadata = JSON.parse(await readFile(metadataPath, "utf8"));
const failures = [];

checkCharacters("name", metadata.name, 2, 30);
checkCharacters("subtitle", metadata.subtitle, 0, 30);
checkCharacters("promotionalText", metadata.promotionalText, 0, 170);
checkCharacters("description", metadata.description, 1, 4_000);
checkCharacters("whatsNew", metadata.whatsNew, 0, 4_000);

const keywordBytes = Buffer.byteLength(metadata.keywords ?? "", "utf8");
if (keywordBytes === 0 || keywordBytes > 100) {
  failures.push(`keywords must use 1...100 UTF-8 bytes; found ${keywordBytes}`);
}

if (failures.length > 0) {
  process.stderr.write("App Store metadata validation failed:\n");
  for (const failure of failures) {
    process.stderr.write(`- ${failure}\n`);
  }
  process.exitCode = 1;
} else {
  process.stdout.write(
    `App Store metadata validation passed (${keywordBytes} keyword bytes).\n`,
  );
}

function checkCharacters(field, value, minimum, maximum) {
  const count = Array.from(value ?? "").length;
  if (count < minimum || count > maximum) {
    failures.push(
      `${field} must use ${minimum}...${maximum} characters; found ${count}`,
    );
  }
}
