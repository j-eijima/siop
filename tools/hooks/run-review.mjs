// Keep JSON on stdout, report liveness on stderr, and bound a silent reviewer.
// Each run has its own POSIX process group so cancellation also reaches the CLI.
import { spawn } from "node:child_process";

const seconds = Number(process.env.PRE_PUSH_REVIEW_TIMEOUT_SECONDS ?? 600);
if (!Number.isInteger(seconds) || seconds < 1 || seconds > 86400) {
    console.error("pre-push: PRE_PUSH_REVIEW_TIMEOUT_SECONDS must be 1–86400");
    process.exit(1);
}
const [companion, ...args] = process.argv.slice(2);
if (!companion) process.exit(1);
const started = Date.now();
const child = spawn(process.execPath, [companion, ...args], {
    detached: true,
    stdio: ["ignore", "inherit", "inherit"],
});
let stopping = false;
const killGroup = (signal) => {
    if (!child.pid) return;
    try { process.kill(-child.pid, signal); }
    catch (error) { if (error.code !== "ESRCH") console.error(error.message); }
};
const heartbeat = setInterval(() => {
    console.error(`pre-push: review still running (${Math.floor((Date.now() - started) / 1000)}s; limit ${seconds}s)`);
}, 30000);
const stop = (reason, code) => {
    if (stopping) return;
    stopping = true;
    clearTimeout(deadline);
    clearInterval(heartbeat);
    console.error(`pre-push: ${reason}; cancelling review`);
    killGroup("SIGTERM");
    // Keep the wrapper alive through the grace period even if the parent CLI
    // exits first, so a descendant ignoring SIGTERM is still cleaned up.
    setTimeout(() => {
        killGroup("SIGKILL");
        process.exit(code);
    }, 2000);
};
const deadline = setTimeout(() => stop(`review timed out after ${seconds}s`, 1), seconds * 1000);
process.on("SIGINT", () => stop("review interrupted", 130));
process.on("SIGTERM", () => stop("review terminated", 143));
child.on("error", (error) => {
    console.error(`pre-push: could not start reviewer: ${error.message}`);
    clearTimeout(deadline);
    clearInterval(heartbeat);
    process.exit(1);
});
child.on("exit", (code, signal) => {
    if (stopping) return;
    clearTimeout(deadline);
    clearInterval(heartbeat);
    if (signal) console.error(`pre-push: reviewer exited on ${signal}`);
    process.exit(code ?? 1);
});
