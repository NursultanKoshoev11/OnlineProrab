"use strict";

// Fails on high/critical npm advisories, except explicitly accepted ones.
// Every exception must name the advisory, explain why it is acceptable and
// expire, so it is re-reviewed instead of silently living forever.
const { spawnSync } = require("node:child_process");

const acceptedAdvisories = [
  {
    id: "GHSA-fc5q-39xc-vjpf",
    reason:
      "picomatch ReDoS via extglobs; no patched release exists (<=4.0.7 is the latest). " +
      "Reached only through the Tailwind CLI file watcher at build time with " +
      "project-controlled glob patterns; nothing ships to the production site.",
    expires: "2027-01-31",
  },
];

const blockingSeverities = new Set(["high", "critical"]);

function advisoryId(url) {
  return String(url || "")
    .split("/")
    .pop();
}

const result = spawnSync("npm", ["audit", "--json"], {
  encoding: "utf8",
  shell: process.platform === "win32",
});
let report;
try {
  report = JSON.parse(result.stdout);
} catch (error) {
  console.error("npm audit did not return a JSON report:", result.stderr);
  process.exit(2);
}
if (report.error) {
  console.error("npm audit failed:", report.error.summary || report.error);
  process.exit(2);
}

const today = new Date().toISOString().slice(0, 10);
const accepted = new Map(acceptedAdvisories.map((entry) => [entry.id, entry]));
const blocking = [];
const ignored = new Set();

for (const [name, vulnerability] of Object.entries(
  report.vulnerabilities || {},
)) {
  for (const via of vulnerability.via || []) {
    if (typeof via === "string") continue; // transitive; the root advisory is listed too
    if (!blockingSeverities.has(via.severity)) continue;
    const id = advisoryId(via.url);
    const exception = accepted.get(id);
    if (exception && exception.expires >= today) {
      ignored.add(id);
      continue;
    }
    const note = exception
      ? ` (exception expired on ${exception.expires})`
      : "";
    blocking.push(`${name}: ${via.severity} ${id} ${via.title}${note}`);
  }
}

for (const id of ignored) {
  const entry = accepted.get(id);
  console.log(`Accepted ${id} until ${entry.expires}: ${entry.reason}`);
}
if (blocking.length > 0) {
  console.error("Blocking npm advisories:");
  for (const line of blocking) console.error(`- ${line}`);
  process.exit(1);
}
console.log("No blocking high or critical npm advisories.");
