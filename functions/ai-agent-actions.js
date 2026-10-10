'use strict';
// The whitelist: the ONLY actions the AI Admin Agent may ever propose. Each
// entry describes WHAT it does (for the preview) and exactly which existing
// write shape or callable performs it — never a new business-logic path. This
// file is read by both ai-agent-executor.js (validation) and the client,
// which receives the matching descriptor back from confirmAgentAction and
// executes it through the app's EXISTING Store.save()/httpsCallable() code —
// so even the executor never re-implements vendor/staff/layout logic itself.
//
// tier: 'readonly' (pure data read, never writes) | 'safe' (direct content/
// layout change, no PIN needed) | 'sensitive' (approvals/suspensions/pricing
// — needs the Agent PIN) | 'critical' (auth/security — needs a fresh OTP
// round). Adding a new action never requires touching the executor; removing
// one here immediately and completely disables it everywhere.

const actions = {
  setTickerText: {
    tier: 'safe',
    module: 'content',
    describe: p => `Set the scrolling ticker text to: "${p.text}"`,
    validate: p => {
      const text = String(p.text ?? '').trim();
      if (!text || text.length > 2000) throw new Error('Provide ticker text (1-2000 characters).');
      return {text};
    },
    kind: 'firestoreMerge',
    collection: 'settings',
    docId: () => 'scrollingText',
    data: p => ({text: p.text}),
  },
  setPromotionField: {
    tier: 'safe',
    module: 'content',
    describe: p => `Set "${p.field}" on promotion ${p.promotionId} to: ${p.value}`,
    validate: p => {
      const promotionId = String(p.promotionId ?? '').trim();
      const field = String(p.field ?? '').trim();
      if (!promotionId || !field) throw new Error('Provide a promotion id and field name.');
      if (p.value === undefined || p.value === null) throw new Error('Provide a value.');
      return {promotionId, field, value: p.value};
    },
    kind: 'firestoreMerge',
    collection: 'promotions',
    docId: p => p.promotionId,
    data: p => ({[p.field]: p.value}),
  },
  reorderSection: {
    tier: 'safe',
    module: 'layout',
    describe: p => `Move the "${p.layoutKey}" homepage section to position ${p.order}`,
    validate: p => {
      const layoutKey = String(p.layoutKey ?? '').trim();
      const order = Number(p.order);
      if (!layoutKey) throw new Error('Provide a section layout key.');
      if (!Number.isFinite(order)) throw new Error('Provide a numeric order.');
      return {layoutKey, order};
    },
    kind: 'firestoreMerge',
    collection: 'settings',
    docId: p => `section_${p.layoutKey}`,
    data: p => ({order: p.order}),
  },
  resizeSection: {
    tier: 'safe',
    module: 'layout',
    describe: p => `Set the "${p.layoutKey}" homepage section's height to ${p.height}`,
    validate: p => {
      const layoutKey = String(p.layoutKey ?? '').trim();
      const height = Number(p.height);
      if (!layoutKey) throw new Error('Provide a section layout key.');
      if (!Number.isFinite(height) || height < 0) throw new Error('Provide a non-negative height.');
      return {layoutKey, height};
    },
    kind: 'firestoreMerge',
    collection: 'settings',
    docId: p => `section_${p.layoutKey}`,
    data: p => ({height: p.height}),
  },
  suspendVendor: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Suspend vendor ${p.vendorId} (reason: ${p.reason})`,
    validate: p => {
      const vendorId = String(p.vendorId ?? '').trim();
      const reason = String(p.reason ?? '').trim();
      if (!vendorId) throw new Error('Provide a vendor id.');
      if (reason.length < 3) throw new Error('Provide a suspension reason of at least 3 characters.');
      return {vendorId, reason};
    },
    kind: 'callable',
    callableName: 'setVendorSuspension',
    callableData: p => ({vendorId: p.vendorId, suspended: true, reason: p.reason}),
  },
  reinstateVendor: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Reinstate vendor ${p.vendorId}`,
    validate: p => {
      const vendorId = String(p.vendorId ?? '').trim();
      if (!vendorId) throw new Error('Provide a vendor id.');
      return {vendorId};
    },
    kind: 'callable',
    callableName: 'setVendorSuspension',
    callableData: p => ({vendorId: p.vendorId, suspended: false, reason: ''}),
  },
  approveVendorApplication: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Approve vendor application ${p.vendorId}`,
    validate: p => {
      const vendorId = String(p.vendorId ?? '').trim();
      if (!vendorId) throw new Error('Provide a vendor id.');
      return {vendorId};
    },
    kind: 'callable',
    callableName: 'approveVendor',
    callableData: p => ({vendorId: p.vendorId, approved: true, feeRequired: false, feeAmount: 0, reason: ''}),
  },
  rejectVendorApplication: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Reject vendor application ${p.vendorId} (reason: ${p.reason})`,
    validate: p => {
      const vendorId = String(p.vendorId ?? '').trim();
      const reason = String(p.reason ?? '').trim();
      if (!vendorId) throw new Error('Provide a vendor id.');
      if (!reason) throw new Error('Provide a rejection reason.');
      return {vendorId, reason};
    },
    kind: 'callable',
    callableName: 'approveVendor',
    callableData: p => ({vendorId: p.vendorId, approved: false, reason: p.reason}),
  },
  suspendStaff: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Suspend field staff ${p.staffUid} (reason: ${p.reason})`,
    validate: p => {
      const staffUid = String(p.staffUid ?? '').trim();
      const reason = String(p.reason ?? '').trim();
      if (!staffUid) throw new Error('Provide a staff uid.');
      if (reason.length < 3) throw new Error('Provide a suspension reason of at least 3 characters.');
      return {staffUid, reason};
    },
    kind: 'callable',
    callableName: 'setFieldStaffSuspension',
    callableData: p => ({staffUid: p.staffUid, suspended: true, reason: p.reason}),
  },
  reinstateStaff: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Reinstate field staff ${p.staffUid}`,
    validate: p => {
      const staffUid = String(p.staffUid ?? '').trim();
      if (!staffUid) throw new Error('Provide a staff uid.');
      return {staffUid};
    },
    kind: 'callable',
    callableName: 'setFieldStaffSuspension',
    callableData: p => ({staffUid: p.staffUid, suspended: false, reason: ''}),
  },
  approveStaffRequest: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Approve field staff access request ${p.staffUid}`,
    validate: p => {
      const staffUid = String(p.staffUid ?? '').trim();
      if (!staffUid) throw new Error('Provide a staff uid.');
      return {staffUid};
    },
    kind: 'callable',
    callableName: 'reviewFieldStaff',
    callableData: p => ({staffUid: p.staffUid, approved: true, reason: ''}),
  },
  rejectStaffRequest: {
    tier: 'sensitive',
    module: 'approvals',
    describe: p => `Reject field staff access request ${p.staffUid} (reason: ${p.reason})`,
    validate: p => {
      const staffUid = String(p.staffUid ?? '').trim();
      const reason = String(p.reason ?? '').trim();
      if (!staffUid) throw new Error('Provide a staff uid.');
      if (!reason) throw new Error('Provide a rejection reason.');
      return {staffUid, reason};
    },
    kind: 'callable',
    callableName: 'reviewFieldStaff',
    callableData: p => ({staffUid: p.staffUid, approved: false, reason: p.reason}),
  },

  // ---- Master Agent integration writes. Unlike every entry above, the
  // CLIENT has no existing capability to call GitHub/Play Console at all
  // (no app callable, no Store.save shape) and their credentials must never
  // reach the client — so these use kind:'serverAction': the server itself
  // performs the write inside confirmAgentAction, using the named
  // integration module's own function, after the usual critical-tier OTP
  // gate. `integration`/`writeFn` are plain strings (never a `require`),
  // keeping this file pure whitelist data with zero business logic, exactly
  // like every entry above it.
  mergeGithubPullRequest: {
    tier: 'critical',
    module: 'github',
    minRole: 'owner',
    describe: p => `Merge pull request #${p.prNumber} in ${p.repo} (${p.mergeMethod})`,
    validate: p => {
      const repo = String(p.repo ?? '').trim();
      const prNumber = Number(p.prNumber);
      const mergeMethod = String(p.mergeMethod ?? 'merge').trim();
      if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Provide a repo as "owner/name".');
      if (!Number.isInteger(prNumber) || prNumber <= 0) throw new Error('Provide a valid pull request number.');
      if (!['merge', 'squash', 'rebase'].includes(mergeMethod)) throw new Error('mergeMethod must be merge, squash, or rebase.');
      return {repo, prNumber, mergeMethod};
    },
    kind: 'serverAction',
    integration: 'github',
    writeFn: 'mergePullRequest',
  },
  createGithubRelease: {
    tier: 'critical',
    module: 'github',
    minRole: 'owner',
    describe: p => `Create GitHub release ${p.tagName} in ${p.repo}`,
    validate: p => {
      const repo = String(p.repo ?? '').trim();
      const tagName = String(p.tagName ?? '').trim();
      if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Provide a repo as "owner/name".');
      if (!tagName) throw new Error('Provide a tag name.');
      return {repo, tagName, name: String(p.name ?? '').trim(), body: String(p.body ?? '').trim()};
    },
    kind: 'serverAction',
    integration: 'github',
    writeFn: 'createRelease',
  },
  deleteGithubBranch: {
    tier: 'critical',
    module: 'github',
    minRole: 'owner',
    describe: p => `Delete branch ${p.branch} in ${p.repo}`,
    validate: p => {
      const repo = String(p.repo ?? '').trim();
      const branch = String(p.branch ?? '').trim();
      if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Provide a repo as "owner/name".');
      if (!branch || branch === 'main' || branch === 'master') throw new Error('Provide a non-default branch name to delete.');
      return {repo, branch};
    },
    kind: 'serverAction',
    integration: 'github',
    writeFn: 'deleteBranch',
  },
  dispatchGithubWorkflow: {
    tier: 'critical',
    module: 'github',
    minRole: 'owner',
    describe: p => `Run workflow ${p.workflowId} in ${p.repo} on ${p.ref}`,
    validate: p => {
      const repo = String(p.repo ?? '').trim();
      const workflowId = String(p.workflowId ?? '').trim();
      if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Provide a repo as "owner/name".');
      if (!workflowId) throw new Error('Provide a workflow file name or id.');
      return {repo, workflowId, ref: String(p.ref ?? 'main').trim(), inputs: typeof p.inputs === 'object' && p.inputs ? p.inputs : {}};
    },
    kind: 'serverAction',
    integration: 'github',
    writeFn: 'dispatchWorkflow',
  },
  setPlayConsoleTrackRollout: {
    tier: 'critical',
    module: 'playConsole',
    minRole: 'owner',
    describe: p => `Set ${p.track} track rollout to ${Math.round(p.userFraction * 100)}% (${p.packageName || 'configured app'})`,
    validate: p => {
      const track = String(p.track ?? '').trim();
      const userFraction = Number(p.userFraction);
      if (!['internal', 'alpha', 'beta', 'production'].includes(track)) throw new Error('Provide a track: internal, alpha, beta, or production.');
      if (!Number.isFinite(userFraction) || userFraction <= 0 || userFraction > 1) throw new Error('Provide a rollout fraction between 0 and 1.');
      return {packageName: String(p.packageName ?? '').trim() || undefined, track, userFraction};
    },
    kind: 'serverAction',
    integration: 'playConsole',
    writeFn: 'setTrackRollout',
  },
};

module.exports = {actions};
