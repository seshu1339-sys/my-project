#!/usr/bin/env node
// Cost cuts part 3 (owner, 18 Nov 2026): the US bucket for every problem screenshot (functions/problem-shots.js). us-central1 is inside
// the Cloud Storage free tier (5 GB stored, 5,000 uploads and 50,000 reads a month; checked 18 Nov 2026: the function code copies
// already in us-central1 use about 0.5 GB of it). The Mumbai bucket has no free tier.
//   * private: uniform access, public access prevented (only the functions' service account reads and writes it)
//   * every file is deleted 30 days after it was saved (lifecycle rule); a solved problem's files go at once (the functions)
//   * no soft delete (deleted files would still be kept, and counted, for 7 days)
//
//   node scripts/problem-shots-bucket.cjs          show the commands only
//   node scripts/problem-shots-bucket.cjs --run    make the bucket (a deploy step: only with the owner's OK)
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execSync} = require('node:child_process');

const PROJECT = 'e-commerce-app-a3897';
const BUCKET = 'e-commerce-app-a3897-problem-shots'; // the same name as functions/problem-shots.js DEFAULT_BUCKET
const run = process.argv.includes('--run');
const lifecycle = path.join(os.tmpdir(), 'problem-shots-lifecycle.json');
fs.writeFileSync(lifecycle, JSON.stringify({rule: [{action: {type: 'Delete'}, condition: {age: 30}}]}));

const commands = [
  `gcloud storage buckets create gs://${BUCKET} --project=${PROJECT} --location=us-central1 --default-storage-class=STANDARD --uniform-bucket-level-access --public-access-prevention --soft-delete-duration=0`,
  `gcloud storage buckets update gs://${BUCKET} --project=${PROJECT} --lifecycle-file="${lifecycle}"`,
  `gcloud storage buckets describe gs://${BUCKET} --project=${PROJECT} --format="yaml(location,storage_class,lifecycle_config,soft_delete_policy,public_access_prevention)"`,
];
for (const c of commands) {
  console.log(`> ${c}`);
  if (run) execSync(c, {stdio: 'inherit'});
}
if (!run) console.log('\nNothing was made. Run with --run only after the owner says OK to deploy.');
