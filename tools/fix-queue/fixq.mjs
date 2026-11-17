// The fix queue of the admin AI Agent (AI Agent + Health System part 4, 17 Nov 2026), for Claude Code on the owner's PC.
// The admin presses Fix / Don't fix / OK / Undo in the admin panel (lib/ui/fix_agent_page.dart); this tool reads those requests and
// writes the fix's progress back, with the owner's own Google login on this PC (gcloud auth). It never
// deploys anything itself: README.md says what Claude Code does at each step, and nothing goes live before the admin's OK.
//
//   node tools/fix-queue/fixq.mjs list                         the requests that need the agent (requested, approved, undoRequested)
//   node tools/fix-queue/fixq.mjs show <id>                    one request in full (JSON)
//   node tools/fix-queue/fixq.mjs claim <id>                   requested -> working
//   node tools/fix-queue/fixq.mjs ready <id> --kind <website|admin|server|design|app> --summary "<text>" --tests "<text>"
//                                  --diff <file> [--branch <b>] [--cost "<text>"] [--tokens-in n --tokens-out n]
//                                                              working -> ready (the admin sees it; one line in the AI usage counter)
//   node tools/fix-queue/fixq.mjs deploying <id>               approved -> deploying
//   node tools/fix-queue/fixq.mjs live <id> --commit <sha> --how "<what went live>" [--backup <ref>]
//                                                              deploying -> live; the problem is solved (its reports too)
//   node tools/fix-queue/fixq.mjs failed <id> --note "<text>"  -> failed (the admin types what to do next)
//   node tools/fix-queue/fixq.mjs undone <id> --commit <sha>   undoRequested -> undone
//
// Every call also marks the agent as running (fixAgent/status.seenAt, shown in the admin panel).
import {readFileSync} from 'node:fs';
import {execSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../functions/package.json'));
const {Firestore, FieldValue} = require('@google-cloud/firestore');
const {OAuth2Client} = require('google-auth-library');

const PROJECT = process.env.FIX_QUEUE_PROJECT || 'e-commerce-app-a3897';
const MAX_DIFF = 90 * 1024;
// The owner's own gcloud login on this PC (the same one the deploys use); no key file.
const token = execSync('gcloud auth print-access-token', {encoding: 'utf8', shell: true}).trim();
const auth = new OAuth2Client();
auth.setCredentials({access_token: token});
const db = new Firestore({projectId: PROJECT, authClient: auth});

const [, , command, id, ...rest] = process.argv;
const flag = name => {
  const i = rest.indexOf(`--${name}`);
  return i >= 0 ? rest[i + 1] : undefined;
};
const fail = message => {
  console.error(message);
  process.exit(1);
};

/// Moves request [id] from one of [from] to [to] with [extra] fields, in a transaction (another step in between stops it).
async function move(from, to, extra = {}) {
  if (!id) fail('Give the request id.');
  const ref = db.collection('fixRequests').doc(id);
  await db.runTransaction(async tx => {
    const doc = await tx.get(ref);
    if (!doc.exists) fail(`No fix request ${id}.`);
    const status = doc.data().status;
    if (!from.includes(status)) fail(`Request ${id} is "${status}", not ${from.join(' / ')}.`);
    tx.update(ref, {status: to, ...extra, [`${to}At`]: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  });
  await log(`fix_${to}`, extra);
  console.log(`${id}: ${from.join('/')} -> ${to}`);
}

async function log(action, details = {}) {
  const small = Object.fromEntries(Object.entries(details).filter(([k]) => k !== 'diff').map(([k, v]) => [k, typeof v === 'string' ? v.slice(0, 300) : v]));
  await db.collection('agentLog').add({uid: 'fix-agent', email: '', action, command: '', target: id || '', platform: 'pc', details: small, at: FieldValue.serverTimestamp()});
}

await db.collection('fixAgent').doc('status').set({seenAt: FieldValue.serverTimestamp(), host: process.env.COMPUTERNAME || 'pc'}, {merge: true});

switch (command) {
  case 'list': {
    const q = await db.collection('fixRequests').where('status', 'in', ['requested', 'approved', 'undoRequested']).limit(50).get();
    const list = q.docs.map(d => ({id: d.id, status: d.data().status, title: d.data().title, problemId: d.data().problemId, instruction: d.data().instruction || '', fixKind: d.data().fixKind || ''}));
    console.log(JSON.stringify(list, null, 2));
    break;
  }
  case 'show': {
    const d = await db.collection('fixRequests').doc(id).get();
    if (!d.exists) fail(`No fix request ${id}.`);
    const data = d.data();
    // The problem's latest cases, for the agent to see where it happens.
    const cases = await db.collection('appCases').where('problemId', '==', data.problemId).limit(10).get();
    console.log(JSON.stringify({id, ...data, cases: cases.docs.map(c => {
      const {phone, uid, ...rest} = c.data();
      return {...rest, uid: uid ? 'signed-in' : '', at: rest.at?.toDate?.()};
    })}, (k, v) => (v && typeof v.toDate === 'function' ? v.toDate() : v), 2));
    break;
  }
  case 'claim':
    await move(['requested'], 'working');
    break;
  case 'ready': {
    const kind = flag('kind');
    if (!['website', 'admin', 'server', 'design', 'app'].includes(kind)) fail('--kind must be website, admin, server, design or app.');
    const diffFile = flag('diff');
    const diff = diffFile ? readFileSync(diffFile, 'utf8') : '';
    const files = [...new Set([...diff.matchAll(/^\+\+\+ b\/(.+)$/gm)].map(m => m[1]))];
    // The AI usage counter (Settings > AI provider & usage counts aiCallLog): one line per fix, with the tokens when known.
    await db.collection('aiCallLog').add({
      feature: 'fix_agent', model: 'claude-code (this PC)', uid: 'fix-agent', stopReason: '', fixRequest: id,
      inputTokens: Number(flag('tokens-in') || 0), outputTokens: Number(flag('tokens-out') || 0), at: FieldValue.serverTimestamp(),
    });
    await move(['working'], 'ready', {
      fixKind: kind, summary: flag('summary') || '', tests: flag('tests') || '', branch: flag('branch') || '',
      cost: flag('cost') || 'Claude Code on this PC (your Claude plan; not the API key)', files,
      diff: diff.length > MAX_DIFF ? `${diff.slice(0, MAX_DIFF)}\n… (cut: the full change is on branch ${flag('branch') || '?'})` : diff,
    });
    break;
  }
  case 'deploying':
    await move(['approved'], 'deploying');
    break;
  case 'live': {
    const commit = flag('commit');
    if (!commit) fail('--commit is needed (the backup is the commit before it).');
    const req = (await db.collection('fixRequests').doc(id).get()).data();
    await move(['deploying', 'approved'], 'live', {commit, how: flag('how') || '', backup: flag('backup') || `${commit}^`});
    // The problem is solved: its reports become Solved and each person is told, its screenshots go (functions react to this).
    if (req?.problemId) await db.collection('solvedProblems').add({problemId: req.problemId, by: 'fix-agent', at: FieldValue.serverTimestamp(), how: `fix ${id}`});
    break;
  }
  case 'failed':
    await move(['working', 'approved', 'deploying', 'undoRequested'], 'failed', {note: flag('note') || 'The fix did not work.'});
    break;
  case 'undone':
    await move(['undoRequested'], 'undone', {undoCommit: flag('commit') || ''});
    break;
  default:
    fail('Commands: list, show, claim, ready, deploying, live, failed, undone (see the top of this file).');
}
process.exit(0);
