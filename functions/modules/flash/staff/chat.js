'use strict';
// The staff chat: its own categories, rules and data. It never reads tickets. Each fact is read with the staff member's uid from the
// server, and only what the chosen category needs.
const {countByStatus} = require('../rules');

async function workFacts(db, uid) {
  const [entries, additions] = await Promise.all(['fieldSubmissions', 'staffAdditions'].map(name => db.collection(name).where('staffUid', '==', uid).select('status').get()));
  return {
    fieldEntries: countByStatus(entries.docs.map(doc => doc.data())),
    vendorsAndProvidersAdded: countByStatus(additions.docs.map(doc => doc.data())),
  };
}

async function accountFacts(db, uid) {
  const staff = (await db.collection('fieldStaff').doc(uid).get()).data() ?? {};
  return {status: staff.status, staffCode: staff.staffCode ?? '', name: staff.name ?? ''};
}

module.exports = {
  kind: 'staff',
  collection: 'flashStaffChats',
  categories: ['Work', 'Account', 'App', 'Other'],
  helpField: 'helpStaff',
  rules: 'You are talking with a field staff member. Help with their own work counts, their account and using the staff app. A pay question, a rejected entry they disagree with or a suspended account needs the team.',

  /// Only someone with a staff record, whatever its status: a suspended member can still ask for help.
  allowed: async (db, uid) => (await db.collection('fieldStaff').doc(uid).get()).exists,
  label: async (db, uid) => {
    const staff = (await db.collection('fieldStaff').doc(uid).get()).data();
    return [staff?.name, staff?.staffCode].filter(Boolean).join(' · ');
  },
  facts: async (db, uid, category) => {
    if (category === 'Work') return workFacts(db, uid);
    if (category === 'Account') return accountFacts(db, uid);
    return {};
  },
};
