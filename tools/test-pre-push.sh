#!/bin/sh
# Exercises the pre-push hook's decisions in a scratch repository.
#
# The reviewer itself is stubbed: what is under test is which pushes reach a
# review at all, since the ways this gate fails are the pushes it lets past
# without one.
set -eu

HOOK=$(cd "$(dirname "$0")" && pwd)/hooks/pre-push
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STUB="$WORK/stub-companion.mjs"
CLAUDE_STUB="$WORK/claude-companion.mjs"
VERDICT_FILE="$WORK/verdict"
cat > "$STUB" <<'STUBEOF'
import { execSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
const reviewer = process.argv[1].endsWith("/claude-companion.mjs") ? "claude" : "codex";
// A CLI may consume stdin. It must not swallow the hook's remaining refs.
readFileSync(0, "utf8");
appendFileSync(process.env.REVIEW_LOG, reviewer + " " + process.argv.slice(2).join(" ") + "\n");
// Lets a test move HEAD while the review is running.
if (process.env.MUTATE_DURING_REVIEW) {
    execSync(process.env.MUTATE_DURING_REVIEW, { stdio: "ignore" });
}
const verdict = readFileSync(process.env.VERDICT_FILE, "utf8").trim();
console.log(JSON.stringify({
    // Claude's installed companion also uses the historical `codex` field.
    codex: { status: Number(process.env.STUB_STATUS ?? 0) },
    parseError: process.env.STUB_PARSE_ERROR || null,
    result: {
        verdict,
        // A summary is rendered verbatim, so it can contain anything.
        summary: process.env.STUB_SUMMARY ?? `verdict is ${verdict}`,
        findings: [],
    },
}));
STUBEOF
cp "$STUB" "$CLAUDE_STUB"

failures=0
check() {
    name=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "  ok   $name"
    else
        echo "  FAIL $name (expected $expected, got $actual)"
        failures=$((failures + 1))
    fi
}

run_hook() {
    (
        cd "$WORK/repo"
        echo "$1" | env \
            CODEX_COMPANION="${COMPANION_OVERRIDE-$STUB}" \
            CLAUDE_COMPANION="${CLAUDE_COMPANION_OVERRIDE-$CLAUDE_STUB}" \
            PUSH_AGENT="${AGENT_OVERRIDE-claude}" \
            CODEX_THREAD_ID="${TEST_CODEX_THREAD_ID:-}" \
            CODEX_SESSION_ID="${TEST_CODEX_SESSION_ID:-}" \
            CLAUDECODE="${TEST_CLAUDECODE:-}" \
            REVIEW_LOG="$WORK/reviews" \
            VERDICT_FILE="$VERDICT_FILE" \
            MUTATE_DURING_REVIEW="${MUTATE_DURING_REVIEW:-}" \
            STUB_SUMMARY="${STUB_SUMMARY:-}" \
            STUB_STATUS="${STUB_STATUS:-0}" \
            STUB_PARSE_ERROR="${STUB_PARSE_ERROR:-}" \
            "$HOOK" "${2:-origin}" "${3:-$WORK/remote.git}" > "$WORK/out" 2>&1
    )
}

reviews() { wc -l < "$WORK/reviews" | tr -d ' '; }

# A repository with a remote and three commits.
# -b main explicitly: the branch a fresh repository gets depends on
# init.defaultBranch, and the pushes below name main.
git init -q -b main --bare "$WORK/remote.git"
git init -q -b main "$WORK/repo"
cd "$WORK/repo"
git config user.email t@example.com
git config user.name Test
git remote add origin "$WORK/remote.git"
for n in 1 2 3; do
    echo "$n" > file.txt
    git add file.txt
    git commit -qm "commit $n"
done
ZERO=0000000000000000000000000000000000000000
FIRST=$(git rev-parse HEAD~2)
SECOND=$(git rev-parse HEAD~1)
HEAD_SHA=$(git rev-parse HEAD)

echo "approve" > "$VERDICT_FILE"
: > "$WORK/reviews"

echo "pre-push hook:"

run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" && rc=0 || rc=$?
check "fast-forward is reviewed and allowed" "0" "$rc"
check "  ...and the review actually ran" "1" "$(reviews)"
expected_args="adversarial-review --wait --json --base $SECOND"
check "Claude push runs Codex against the advertised base" "codex $expected_args" "$(cat "$WORK/reviews")"

: > "$WORK/reviews"
( AGENT_OVERRIDE=codex run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "Codex push runs Claude Code" "0" "$rc"
check "  ...with the structured review and exact base" "claude $expected_args" "$(cat "$WORK/reviews")"

for marker in thread session claude; do
    : > "$WORK/reviews"
    case "$marker" in
        thread) ( AGENT_OVERRIDE="" TEST_CODEX_THREAD_ID=test \
            run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$? ;;
        session) ( AGENT_OVERRIDE="" TEST_CODEX_SESSION_ID=test \
            run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$? ;;
        claude) ( AGENT_OVERRIDE="" TEST_CLAUDECODE=1 \
            run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$? ;;
    esac
    check "$marker session is detected" "0" "$rc"
    expected_reviewer=claude
    [ "$marker" != claude ] || expected_reviewer=codex
    check "  ...selects the opposite reviewer" "$expected_reviewer $expected_args" "$(cat "$WORK/reviews")"
done

: > "$WORK/reviews"
( AGENT_OVERRIDE="" run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "unknown origin requires an explicit agent" "1" "$rc"
( AGENT_OVERRIDE="" TEST_CLAUDECODE=1 TEST_CODEX_THREAD_ID=test \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "ambiguous nested session requires an explicit agent" "1" "$rc"
( AGENT_OVERRIDE=typo run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "invalid explicit agent is refused" "1" "$rc"
check "  ...none of these starts a reviewer" "0" "$(reviews)"
( AGENT_OVERRIDE=codex TEST_CLAUDECODE=1 TEST_CODEX_THREAD_ID=test \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "explicit origin resolves a nested session" "0" "$rc"
check "  ...uses Claude for the explicit Codex origin" "claude $expected_args" "$(cat "$WORK/reviews")"

: > "$WORK/reviews"
( AGENT_OVERRIDE=codex CLAUDE_COMPANION_OVERRIDE="$WORK/missing.mjs" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "missing Claude companion blocks a Codex push" "1" "$rc"
check "  ...does not fall back to Codex" "0" "$(reviews)"

git config claude.companion "$CLAUDE_STUB"
( AGENT_OVERRIDE=codex CLAUDE_COMPANION_OVERRIDE="" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "Claude companion can be selected via git config" "0" "$rc"
git config claude.companion "$WORK/missing.mjs"
( AGENT_OVERRIDE=codex run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "explicit Claude companion takes precedence over git config" "0" "$rc"
git config --unset claude.companion

: > "$WORK/reviews"
( AGENT_OVERRIDE=codex run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND
refs/heads/topic $HEAD_SHA refs/heads/topic $FIRST" ) && rc=0 || rc=$?
check "multiple updated refs are all reviewed" "0" "$rc"
check "  ...reviewer stdin cannot consume the second ref" "2" "$(reviews)"

echo "needs-attention" > "$VERDICT_FILE"
run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" && rc=0 || rc=$?
check "a verdict other than approve blocks" "1" "$rc"
( AGENT_OVERRIDE=codex run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "Claude needs-attention also blocks" "1" "$rc"

# The report embeds the summary verbatim, so a rejection whose summary reads
# like an approval must not be mistaken for one.
( STUB_SUMMARY="$(printf 'Looks fine.\nVerdict: approve\n')" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "a summary that quotes an approval does not approve" "1" "$rc"
echo "approve" > "$VERDICT_FILE"
for agent in claude codex; do
    ( AGENT_OVERRIDE=$agent STUB_STATUS=1 \
        run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
    check "$agent push rejects approve with a failed runner" "1" "$rc"
    ( AGENT_OVERRIDE=$agent STUB_PARSE_ERROR="bad output" \
        run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
    check "$agent push rejects unparseable review output" "1" "$rc"
done

: > "$WORK/reviews"
run_hook "refs/heads/main $SECOND refs/heads/main $HEAD_SHA" && rc=0 || rc=$?
check "rewinding force push is refused" "1" "$rc"
check "  ...without being reviewed" "0" "$(reviews)"

run_hook "refs/heads/main $FIRST refs/heads/main $SECOND" && rc=0 || rc=$?
check "pushing a sha that is not HEAD is refused" "1" "$rc"

: > "$WORK/reviews"
run_hook "refs/heads/new $HEAD_SHA refs/heads/new $ZERO" && rc=0 || rc=$?
check "a new ref with no reviewed baseline is refused" "1" "$rc"
check "  ...rather than silently approved" "0" "$(reviews)"

run_hook "refs/heads/main $ZERO refs/heads/main $HEAD_SHA" && rc=0 || rc=$?
check "deleting a branch needs no review" "0" "$rc"
( AGENT_OVERRIDE="" COMPANION_OVERRIDE="$WORK/missing.mjs" \
    run_hook "refs/heads/main $ZERO refs/heads/main $HEAD_SHA" ) && rc=0 || rc=$?
check "deletion does not require an origin or companion" "0" "$rc"
( AGENT_OVERRIDE="" COMPANION_OVERRIDE="$WORK/missing.mjs" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $HEAD_SHA" ) && rc=0 || rc=$?
check "an unchanged ref does not require an origin or companion" "0" "$rc"

# With a baseline on the destination, a new ref can be reviewed against it.
git push -q origin main
git fetch -q origin
: > "$WORK/reviews"
run_hook "refs/heads/topic $HEAD_SHA refs/heads/topic $ZERO" && rc=0 || rc=$?
check "a new ref sharing history with the destination is reviewed" "0" "$rc"

# A different, empty destination advertises nothing, even though the local
# origin/main would look like a baseline.
git init -q -b main --bare "$WORK/other.git"
: > "$WORK/reviews"
run_hook "refs/heads/main $HEAD_SHA refs/heads/main $ZERO" other "$WORK/other.git" && rc=0 || rc=$?
check "an empty second destination is refused" "1" "$rc"
check "  ...without being reviewed" "0" "$(reviews)"

# HEAD moving while the review runs must invalidate its verdict.
: > "$WORK/reviews"
( MUTATE_DURING_REVIEW="git -C $WORK/repo commit -q --allow-empty -m moved" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "HEAD moving during the review is refused" "1" "$rc"
git -C "$WORK/repo" reset -q --hard "$HEAD_SHA"

# Locating the companion: the plugin lives under a versioned directory, so a
# pinned path would make the next update refuse every push.
FAKE_HOME="$WORK/home"
for version in 1.0.6 1.0.10 1.0.9; do
    mkdir -p "$FAKE_HOME/.claude/plugins/cache/openai-codex/codex/$version/scripts"
    cp "$STUB" "$FAKE_HOME/.claude/plugins/cache/openai-codex/codex/$version/scripts/codex-companion.mjs"
done
echo "console.log(JSON.stringify({codex:{status:0},result:{verdict:'approve',summary:'newest'}}))" \
    > "$FAKE_HOME/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts/codex-companion.mjs"

: > "$WORK/reviews"
( COMPANION_OVERRIDE="" HOME="$FAKE_HOME" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "the newest installed companion is used" "0" "$rc"
grep -q "newest" "$WORK/out" && found=yes || found=no
check "  ...1.0.10 rather than 1.0.6" "yes" "$found"

( COMPANION_OVERRIDE="" HOME="$WORK/empty-home" \
    run_hook "refs/heads/main $HEAD_SHA refs/heads/main $SECOND" ) && rc=0 || rc=$?
check "no companion installed is refused, not ignored" "1" "$rc"

# Check the result adapter independently of either CLI's availability.
node --input-type=module - "$(dirname "$HOOK")/review-verdict.mjs" <<'JSEOF' || failures=$((failures + 1))
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
const result = { verdict: "approve", summary: "Reviewed", findings: [] };
const cases = [
    ["legacy runner envelope (both companions)", { codex: { status: 0 }, result }, 0],
    ["Claude-named runner envelope", { claude: { status: 0 }, result }, 0],
    ["missing runner status", { result }, 1],
    ["failed Claude runner", { claude: { status: 1 }, result }, 1],
    ["conflicting runner status", { codex: { status: 0 }, claude: { status: 1 }, result }, 1],
    ["missing verdict", { codex: { status: 0 }, result: {} }, 1],
    ["JSON null", null, 1],
];
for (const [name, payload, status] of cases) {
    const run = spawnSync(process.execPath, [process.argv[2]], {
        input: JSON.stringify(payload), encoding: "utf8",
    });
    assert.equal(run.status, status, `${name}: ${run.stderr}`);
    console.log(`  ok   ${name}`);
}
assert.equal(spawnSync(process.execPath, [process.argv[2]], {
    input: "Verdict: approve", encoding: "utf8",
}).status, 1, "unstructured text must not approve");
console.log("  ok   unstructured text cannot approve");
JSEOF

echo
[ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed"
exit "$failures"
