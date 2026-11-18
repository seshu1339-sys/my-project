const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {collection, doc, getDoc, getDocs, limit, orderBy, query, setDoc, setLogLevel, where} = require('firebase/firestore');

// Company messages (cost cuts part 5): nobody but the functions writes one, so no vendor can make a message that looks like the
// company's; a vendor reads only what is for them; staff read the ones they sent.
test('company messages: only functions write; a vendor reads their own and the everyone-list; staff read what they sent', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  setLogLevel('error');
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-company', firestore: {rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      await setDoc(doc(db, 'companyMessages/direct'), {public: false, vendorUids: ['v1'], deleted: false, sentAt: 2, sentBy: {uid: 's1', role: 'staff'}});
      await setDoc(doc(db, 'companyMessages/gone'), {public: false, vendorUids: ['v1'], deleted: true, sentAt: 1, sentBy: {uid: 'admin'}});
      await setDoc(doc(db, 'companyMessages/town'), {public: true, vendorUids: [], deleted: false, sentAt: 3, sentBy: {uid: 'admin'}});
      await setDoc(doc(db, 'companyMessagePhotos/direct'), {data: 'x'});
      await setDoc(doc(db, 'companyMessagePhotos/town'), {data: 'x'});
      await setDoc(doc(db, 'companyMessagePhotos/gone'), {data: 'x'});
      await setDoc(doc(db, 'companyMessagesIndex/vendors'), {items: []});
      await setDoc(doc(db, 'companyMessageReads/v1'), {read: []});
      await setDoc(doc(db, 'companyMessageSenders/main'), {staff: [{uid: 's1'}]});
      await setDoc(doc(db, 'companyAudience/vendors'), {people: []});
      await setDoc(doc(db, '_adminSessions/admin'), {expiresAt: new Date(Date.now() + 3600000)});
    });
    const v1 = env.authenticatedContext('v1', {role: 'vendor', email_verified: true}).firestore();
    const v2 = env.authenticatedContext('v2', {role: 'vendor', email_verified: true}).firestore();
    const s1 = env.authenticatedContext('s1', {role: 'staff', email_verified: true}).firestore();
    const customer = env.authenticatedContext('c1', {role: 'user', email_verified: true}).firestore();
    const admin = env.authenticatedContext('admin', {role: 'admin', email_verified: true, admin: true}).firestore();

    // A vendor: their own messages (the app's query), the everyone-list, the photos of what they may read, their own read record.
    await assertSucceeds(getDocs(query(collection(v1, 'companyMessages'), where('vendorUids', 'array-contains', 'v1'), where('deleted', '==', false), orderBy('sentAt', 'desc'), limit(30))));
    await assertSucceeds(getDoc(doc(v1, 'companyMessages/direct')));
    await assertFails(getDoc(doc(v1, 'companyMessages/gone')), 'deleted: hidden');
    await assertFails(getDoc(doc(v2, 'companyMessages/direct')), 'another vendor\'s message');
    await assertFails(getDocs(collection(v2, 'companyMessages')));
    await assertSucceeds(getDoc(doc(v1, 'companyMessagesIndex/vendors')));
    await assertSucceeds(getDoc(doc(v1, 'companyMessagePhotos/direct')));
    await assertSucceeds(getDoc(doc(v2, 'companyMessagePhotos/town')));
    await assertFails(getDoc(doc(v2, 'companyMessagePhotos/direct')));
    await assertFails(getDoc(doc(v1, 'companyMessagePhotos/gone')));
    await assertSucceeds(getDoc(doc(v1, 'companyMessageReads/v1')));
    await assertFails(getDoc(doc(v2, 'companyMessageReads/v1')));
    // Staff: what they sent; the sender list (to know they may send).
    await assertSucceeds(getDoc(doc(s1, 'companyMessages/direct')));
    await assertFails(getDoc(doc(s1, 'companyMessages/town')));
    await assertSucceeds(getDoc(doc(s1, 'companyMessageSenders/main')));
    await assertFails(getDoc(doc(v1, 'companyMessageSenders/main')));
    // Customers see none of it; the audience cache is for functions only.
    for (const path of ['companyMessages/town', 'companyMessagesIndex/vendors', 'companyMessagePhotos/town', 'companyAudience/vendors']) await assertFails(getDoc(doc(customer, path)));
    await assertFails(getDoc(doc(admin, 'companyAudience/vendors')));
    await assertSucceeds(getDoc(doc(admin, 'companyMessages/gone')), 'the admin log keeps deleted ones');
    // Nobody writes from an app: not a vendor, not staff, not even the admin's browser (only the functions).
    for (const db of [v1, s1, admin]) {
      await assertFails(setDoc(doc(db, 'companyMessages/fake'), {public: true, title: 'LOCAMARKET Team', deleted: false, vendorUids: []}));
      await assertFails(setDoc(doc(db, 'companyMessagesIndex/vendors'), {items: [{id: 'fake', title: 'Pay here'}]}));
      await assertFails(setDoc(doc(db, 'companyMessageReads/v1'), {read: ['x']}));
    }
  } finally { await env.cleanup(); }
});
