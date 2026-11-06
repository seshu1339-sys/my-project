'use strict';
// The service providers' chat (the same basic level as free vendors): signing in, their listing and its approval, their charge per
// hour, using the app. Each fact is read with the provider's uid from the server.
const {dateText} = require('../rules');

async function listingFacts(db, uid) {
  const [application, provider] = await Promise.all([db.collection('providerApplications').doc(uid).get(), db.collection('providers').doc(uid).get()]);
  const app = application.data() ?? {};
  const live = provider.data();
  const listing = live?.listingId ? (await db.collection('services').doc(live.listingId).get()).data() : null;
  return {
    registration: application.exists ? {status: app.status, providerCode: app.providerCode ?? '', service: app.serviceName ?? '', chargePerHour: app.hourlyRate ?? '', registeredOn: dateText(app.submittedAt)} : 'not registered yet',
    listing: listing ? {showingToCustomers: listing.active !== false, service: listing.serviceName ?? '', chargePerHour: listing.price ?? ''} : 'not live yet',
  };
}

module.exports = {
  kind: 'provider',
  collection: 'flashProviderChats',
  categories: ['Login', 'My listing', 'Charge per hour', 'App', 'Other'],
  helpField: 'helpProvider',
  rules: 'You are talking with a service provider (a plumber, electrician, painter and so on). Help with signing in, their listing and its approval, their charge per hour and using the app. Approval and anything about another person needs the team.',

  allowed: async (db, uid) => {
    const [application, provider] = await Promise.all([db.collection('providerApplications').doc(uid).get(), db.collection('providers').doc(uid).get()]);
    return application.exists || provider.exists;
  },
  label: async (db, uid) => {
    const app = (await db.collection('providerApplications').doc(uid).get()).data();
    return [app?.name, app?.providerCode].filter(Boolean).join(' · ');
  },
  facts: async (db, uid, category) => (['Login', 'My listing', 'Charge per hour'].includes(category) ? listingFacts(db, uid) : {}),
};
