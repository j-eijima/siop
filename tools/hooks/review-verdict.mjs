// Decides whether a Codex or Claude Code review approved the change, and renders it.
//
// Reads the companion's --json payload on stdin. The verdict comes from the
// structured result and nothing else: the rendered report embeds the summary
// verbatim, so a summary quoting an approval would fool any search of the
// report text.
//
// Exits 0 only when the review ran, parsed, and returned exactly "approve".

import { readFileSync } from "node:fs";

const fail = (reason) => {
    console.error(`review-verdict: ${reason}`);
    process.exit(1);
};

let payload;
try {
    payload = JSON.parse(readFileSync(0, "utf8"));
} catch (cause) {
    fail(`the review produced no JSON payload (${cause.message})`);
}

if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    fail("the review payload is not an object");
}
if (payload.parseError) {
    fail(`the review output could not be parsed: ${payload.parseError}`);
}
// Both installed companions currently use the historical `codex` envelope.
// Accept `claude` as well, but never accept approval without a successful run.
const runners = [payload.codex, payload.claude].filter(Boolean);
if (runners.length === 0 || runners.some((runner) => runner.status !== 0)) {
    fail("the review has no successful runner status, or a runner failed");
}

const result = payload.result;
if (!result || typeof result.verdict !== "string") {
    fail("the review returned no verdict");
}

if (result.summary) {
    console.log(result.summary);
}
for (const finding of result.findings ?? []) {
    const location = finding.location ?? (finding.file
        ? `${finding.file}:${finding.line_start ?? "?"}` : "");
    const where = location ? ` (${location})` : "";
    console.log(`\n- [${finding.severity ?? "?"}] ${finding.title ?? "finding"}${where}`);
    if (finding.body) console.log(`  ${finding.body}`);
}

if (result.verdict !== "approve") {
    fail(`verdict is "${result.verdict}"`);
}
console.log("\nVerdict: approve");
