#!/usr/bin/env node
// Deletes the Cloud Functions build images right after a deploy (free-limit plan, owner OK 17 Nov 2026): Artifact Registry is free only
// up to 0.5 GB and every deploy adds new images. The running functions do not need them: Cloud Run keeps its own copy of each deployed
// revision (checked 17 Nov 2026: 143 functions started fresh copies after their image was deleted, all answered normally). A later
// deploy builds new images. The 1-day clean-up rule stays as a second net.
//
//   node scripts/clean-function-images.cjs           delete every image in both gcf-artifacts repositories
//   node scripts/clean-function-images.cjs --dry     only list them
const {execSync} = require('node:child_process');

const PROJECT = 'e-commerce-app-a3897';
const REGIONS = ['us-central1', 'asia-south1'];
const dry = process.argv.includes('--dry');
const run = cmd => execSync(cmd, {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});

let deleted = 0;
for (const region of REGIONS) {
  const packages = run(`gcloud artifacts packages list --repository=gcf-artifacts --location=${region} --project=${PROJECT} --format="value(name)"`)
    // Names like "e--commerce--...__set_ai_key" and "e--commerce--...__set_ai_key/cache" (the build cache): keep the whole name.
    .split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('Listing')).map(s => s.replace(/^.*\/packages\//, ''));
  console.log(`${region}: ${packages.length} image packages`);
  for (const p of packages) {
    if (dry) { console.log(`  would delete ${p}`); continue; }
    try {
      run(`gcloud artifacts packages delete "${p}" --repository=gcf-artifacts --location=${region} --project=${PROJECT} --quiet`);
      deleted++;
    } catch (e) {
      console.warn(`  could not delete ${p}: ${String(e.stderr || e.message).split('\n').filter(Boolean).pop()}`);
    }
  }
}
console.log(dry ? 'Dry run: nothing deleted.' : `Deleted ${deleted} image packages.`);
