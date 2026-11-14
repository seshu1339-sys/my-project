'use strict';
// Staff Area System: what this module reads and writes.
//   staffAreaTowns/<townKey>     {town, townKey, radiusKm}: the town's radius (admin)
//   staffAreas/<id>              {name, town, townKey, latitude, longitude, radiusKm, status: free | pending | booked}: public to signed-in
//                                staff (the claim map shows green / red); who holds it is NOT here
//   staffAreaHolders/<areaId>    {staffUid, staffCode, staffName, staffPhone, claimedAt, bookedAt}: admin only
//   staffAreaStaff/<staffUid>    {areaId, termsAcceptedAt, month, missedThisMonth, warning, deactivatedAt, deactivatedReason,
//                                deactivatedAreaId}: the staff member reads their own
//   staffAreaSettings/main       {dailyTarget, maxMissedDays, terms}: read by signed-in staff, written by the admin
//   staffAreaDays/<areaId>_<day> {areaId, staffUid, day, month, week, rateUpdates, worked, outcome: worked | off | missed | warn | deactivate}
//   staffOfferPhotoUses/<photoId> one use of a live photo (a photo can never count twice)
//   vendorOffers/<id>            the staff member's Today's Offers are vendor offers of the shop with source 'staff' (so the customer
//                                apps show them in Today's Offers with the shop and its route); always today's rate, ending at midnight;
//                                the area's own vendors' offers are counted from the same collection
//   fieldStaff/<uid>             read (status, staffCode, name, phone); a deactivation sets status 'suspended' (reason missedDays)
//   shops, productImageLibrary   read
//
// Hexagon cells (owner, 13 Nov 2026), the only way new staff get an area: India is divided into H3 hexagons sized by population
// density (functions/hex-grid.js: 1, 2 or 5 km). Nothing is stored for a free cell. A claimed cell is a staffAreas/<H3 cell> document
// like any other area (so targets, the nightly check, My work and vendor linking work the same), with hex: true, hexCell, hexCode
// (HX1-...), hexSizeKm, hexParent5 (to find the claimed cells near a place) and hexOutline; staffAreaStaff/<uid> keeps the staff
// member's home pin (homeLatitude, homeLongitude, homeAddress, homeDistanceKm). A cell freed later keeps a small record marked free
// (the admin's reactivation gives it back). The older admin areas and automatic blocks stay in the code, unused for new staff.
const {Timestamp, FieldValue} = require('firebase-admin/firestore');
const {publicStorageUrl} = require('../../storage-url');
const R = require('./rules');
const B = require('./blocks');
const G = require('../../hex-grid');

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const settingsRef = db => db.collection('staffAreaSettings').doc('main');
const readSettings = async db => R.settingsOf((await settingsRef(db).get()).data());

async function saveSettings(db, data, now = Date.now()) {
  const fields = R.validateSettings(data);
  await settingsRef(db).set({...fields, updatedAt: Timestamp.fromMillis(now)}, {merge: true});
  return R.settingsOf({...(await settingsRef(db).get()).data()});
}

const areaOf = doc => ({id: doc.id, ...doc.data()});
async function allAreas(db) { return (await db.collection('staffAreas').get()).docs.map(areaOf); }

/// The first area [candidate] would overlap, among [areas] (itself left out).
const overlapWith = (candidate, areas) => areas.find(a => a.id !== candidate.id && R.overlaps(candidate, a));

/// Admin: a town's radius. A new radius is used by every area of the town, unless two of them would then overlap.
async function saveTown(db, data, now = Date.now()) {
  const town = R.validateTown(data);
  const areas = await allAreas(db);
  const resized = areas.map(a => (a.townKey === town.townKey ? {...a, radiusKm: town.radiusKm} : a));
  for (const a of resized.filter(a => a.townKey === town.townKey)) {
    const other = overlapWith(a, resized);
    if (other) throw Error(`With ${town.radiusKm} km, "${a.name}" and "${other.name}" would overlap. Use a smaller radius or move an area first.`);
  }
  const batch = db.batch();
  batch.set(db.collection('staffAreaTowns').doc(town.townKey), {...town, updatedAt: Timestamp.fromMillis(now)}, {merge: true});
  for (const a of areas.filter(a => a.townKey === town.townKey && a.radiusKm !== town.radiusKm)) batch.update(db.collection('staffAreas').doc(a.id), {radiusKm: town.radiusKm});
  await batch.commit();
  return town;
}

/// Admin: adds an area (centre + the town's radius) or edits one. Overlapping areas are refused. A taken area keeps its centre.
async function saveArea(db, data, now = Date.now()) {
  const fields = R.validateArea(data);
  const town = (await db.collection('staffAreaTowns').doc(fields.townKey).get()).data();
  if (!town) throw Error(`Set the radius of ${fields.town} first (Towns).`);
  const at = Timestamp.fromMillis(now);
  const areas = await allAreas(db);
  let ref;
  if (data.areaId) {
    if (typeof data.areaId !== 'string' || !ID.test(data.areaId)) throw Error('That area was not found.');
    ref = db.collection('staffAreas').doc(data.areaId);
    const current = areas.find(a => a.id === data.areaId);
    if (!current) throw Error('That area was not found.');
    const moved = current.latitude !== fields.latitude || current.longitude !== fields.longitude || current.townKey !== fields.townKey;
    if (moved && current.status !== 'free') throw Error('A taken area cannot be moved. Free it first.');
  } else {
    ref = db.collection('staffAreas').doc();
  }
  const candidate = {id: ref.id, ...fields, radiusKm: town.radiusKm};
  const other = overlapWith(candidate, areas);
  if (other) throw Error(`This area would overlap "${other.name}". Move the centre further away.`);
  if (data.areaId) await ref.update({...fields, radiusKm: town.radiusKm, updatedAt: at});
  else await ref.set({...fields, radiusKm: town.radiusKm, status: 'free', createdAt: at, updatedAt: at});
  return {areaId: ref.id};
}

async function deleteArea(db, data) {
  if (typeof data.areaId !== 'string' || !ID.test(data.areaId)) throw Error('That area was not found.');
  const ref = db.collection('staffAreas').doc(data.areaId);
  const area = (await ref.get()).data();
  if (!area) throw Error('That area was not found.');
  if (area.status !== 'free') throw Error('Only a free area can be deleted. Free it first.');
  await ref.delete();
  return {deleted: true};
}

/// A staff member (registered, approved or still waiting) claims a free area, standing inside it, having accepted the Terms.
async function claimArea(db, staffUid, data = {}, now = Date.now()) {
  if (data.termsAccepted !== true) throw Error('Tick "I accept the Terms & Conditions" to finish.');
  if (typeof data.areaId !== 'string' || !ID.test(data.areaId)) throw Error('Choose a free area.');
  const staffRef = db.collection('fieldStaff').doc(staffUid);
  const areaRef = db.collection('staffAreas').doc(data.areaId);
  const mineRef = db.collection('staffAreaStaff').doc(staffUid);
  const holderRef = db.collection('staffAreaHolders').doc(data.areaId);
  return db.runTransaction(async tx => {
    // Every read first (a transaction writes only after its reads).
    const [staffDoc, areaDoc, mineDoc, settingsDoc] = await Promise.all([tx.get(staffRef), tx.get(areaRef), tx.get(mineRef), tx.get(settingsRef(db))]);
    const staff = staffDoc.data();
    if (!staff || !['pending', 'active'].includes(staff.status)) throw Error('Register as staff first.');
    const area = areaDoc.data();
    if (!area) throw Error('That area was not found.');
    if (await heldArea(ref => tx.get(ref), db, mineDoc.data())) throw Error('You already have an area. One staff member has one area.');
    if (area.status !== 'free') throw Error('This area is already taken. Choose a green (free) area.');
    if (!R.inside(area, data.latitude, data.longitude)) throw Error('Please go to this area to register it. Turn on GPS and stand inside the area.');
    const at = Timestamp.fromMillis(now);
    const status = staff.status === 'active' ? 'booked' : 'pending';
    tx.update(areaRef, {status, updatedAt: at});
    tx.set(holderRef, {
      staffUid, staffCode: staff.staffCode || '', staffName: staff.name || staff.displayName || '', staffPhone: staff.phone || '',
      claimedAt: at, ...(status === 'booked' ? {bookedAt: at} : {}),
    });
    const settings = settingsDoc.data();
    tx.set(mineRef, {
      staffUid, areaId: data.areaId, areaName: area.name, town: area.town, termsAcceptedAt: at, termsVersion: settings?.updatedAt ?? null, claimedAt: at,
      ...(status === 'booked' ? {bookedAt: at} : {}),
    }, {merge: true});
    return {areaId: data.areaId, status};
  });
}

/// One staff member (one email ID) has one area, ever at a time: a held, pending or booked area blocks a second one.
async function heldArea(get, db, mine) {
  if (!mine?.areaId) return null;
  const held = (await get(db.collection('staffAreas').doc(mine.areaId))).data();
  return held && held.status !== 'free' ? held : null;
}

/// Whether two areas may not both exist: an automatic area that is free again (its staff member left) never blocks a new one.
const blocks = (area, candidateId) => area.id !== candidateId && !(area.auto === true && area.status === 'free');

const PREVIEWS_A_DAY = 30;

/// The automatic area for a tapped centre (no database writes except the staff member's daily preview count): the block, the
/// buildings counted in OpenStreetMap, the density and the radius. [countBuildings] (lat, lng, radiusM) -> number asks Overpass.
async function autoArea(db, data, countBuildings, settings) {
  const block = B.blockOf(data.latitude, data.longitude);
  const known = (await db.collection('staffAreaBlocks').doc(block.blockId).get()).data();
  const buildings = Number.isInteger(known?.buildings) ? known.buildings : await countBuildings(block.latitude, block.longitude, B.SAMPLE_RADIUS_M);
  const density = B.densityPerKm2(buildings);
  return {...block, buildings, densityPerKm2: density, radiusKm: B.radiusFor(density, settings.densityBands), counted: !known};
}

/// Staff: "what area would this be?" before registering. Says the radius, and whether it is free or too close to another area.
async function previewAutoArea(db, staffUid, data = {}, countBuildings, now = Date.now()) {
  const [staff, mine] = await Promise.all([
    db.collection('fieldStaff').doc(staffUid).get().then(d => d.data()),
    db.collection('staffAreaStaff').doc(staffUid).get().then(d => d.data()),
  ]);
  if (!staff || !['pending', 'active'].includes(staff.status)) throw Error('Register as staff first.');
  if (await heldArea(ref => ref.get(), db, mine)) throw Error('You already have an area. One staff member has one area.');
  const day = R.istDay(now);
  const used = mine?.previewDay === day ? mine.previews || 0 : 0;
  if (used >= PREVIEWS_A_DAY) throw Error(`You checked ${PREVIEWS_A_DAY} places today. Try again tomorrow.`);
  const settings = await readSettings(db);
  const area = await autoArea(db, data, countBuildings, settings);
  await db.collection('staffAreaStaff').doc(staffUid).set({staffUid, previewDay: day, previews: used + 1}, {merge: true});
  const candidate = {id: area.blockId, latitude: area.latitude, longitude: area.longitude, radiusKm: area.radiusKm};
  const others = (await allAreas(db)).filter(a => blocks(a, area.blockId));
  const existing = (await db.collection('staffAreas').doc(area.blockId).get()).data();
  const taken = existing && existing.status !== 'free';
  const near = taken ? null : others.find(a => R.overlaps(candidate, a));
  return {
    blockId: area.blockId, latitude: area.latitude, longitude: area.longitude, buildings: area.buildings, densityPerKm2: area.densityPerKm2, radiusKm: area.radiusKm,
    free: !taken && !near, problem: taken ? 'This block is already taken. Tap another place.' : near ? `Too close to "${near.name}". Tap a place further away.` : '',
  };
}

/// Staff: registers the automatic area of a tapped centre, standing inside it with GPS on, having accepted the Terms. The radius is
/// always the server's (any radius sent is ignored). Only the picked block is saved (staffAreaBlocks keeps its building count).
async function claimAutoArea(db, staffUid, data = {}, countBuildings, now = Date.now()) {
  if (data.termsAccepted !== true) throw Error('Tick "I accept the Terms & Conditions" to finish.');
  const settings = await readSettings(db);
  const area = await autoArea(db, data, countBuildings, settings);
  const name = B.label(data.name, `Area ${area.blockId}`, 80);
  const town = B.label(data.town, name);
  const staffRef = db.collection('fieldStaff').doc(staffUid);
  const mineRef = db.collection('staffAreaStaff').doc(staffUid);
  const areaRef = db.collection('staffAreas').doc(area.blockId);
  const holderRef = db.collection('staffAreaHolders').doc(area.blockId);
  const blockRef = db.collection('staffAreaBlocks').doc(area.blockId);
  const others = (await allAreas(db)).filter(a => blocks(a, area.blockId));
  return db.runTransaction(async tx => {
    const [staffDoc, mineDoc, areaDoc, termsDoc] = await Promise.all([tx.get(staffRef), tx.get(mineRef), tx.get(areaRef), tx.get(settingsRef(db))]);
    const staff = staffDoc.data();
    if (!staff || !['pending', 'active'].includes(staff.status)) throw Error('Register as staff first.');
    if (await heldArea(ref => tx.get(ref), db, mineDoc.data())) throw Error('You already have an area. One staff member has one area.');
    const existing = areaDoc.data();
    if (existing && existing.status !== 'free') throw Error('This block is already taken. Tap another place.');
    const candidate = {id: area.blockId, latitude: area.latitude, longitude: area.longitude, radiusKm: area.radiusKm};
    const near = others.find(a => R.overlaps(candidate, a));
    if (near) throw Error(`Too close to "${near.name}". Tap a place further away.`);
    if (!R.inside(candidate, data.gpsLatitude, data.gpsLongitude)) throw Error('Please go to this area to register it. Turn on GPS and stand inside the area.');
    const at = Timestamp.fromMillis(now);
    const status = staff.status === 'active' ? 'booked' : 'pending';
    if (area.counted) tx.set(blockRef, {blockId: area.blockId, latitude: area.latitude, longitude: area.longitude, buildings: area.buildings, sampleRadiusM: B.SAMPLE_RADIUS_M, countedAt: at});
    tx.set(areaRef, {
      name, town, townKey: R.townKey(town), latitude: area.latitude, longitude: area.longitude, radiusKm: area.radiusKm, status, auto: true,
      blockId: area.blockId, buildings: area.buildings, densityPerKm2: area.densityPerKm2, createdAt: existing?.createdAt ?? at, updatedAt: at,
    });
    tx.set(holderRef, {
      staffUid, staffCode: staff.staffCode || '', staffName: staff.name || staff.displayName || '', staffPhone: staff.phone || '',
      claimedAt: at, ...(status === 'booked' ? {bookedAt: at} : {}),
    });
    tx.set(mineRef, {
      staffUid, areaId: area.blockId, areaName: name, town, termsAcceptedAt: at, termsVersion: termsDoc.data()?.updatedAt ?? null, claimedAt: at,
      ...(status === 'booked' ? {bookedAt: at} : {}),
    }, {merge: true});
    return {areaId: area.blockId, status, radiusKm: area.radiusKm};
  });
}

// ---- Hexagon cells (owner, 13 Nov 2026) ----

/// The staff member's home must be within this distance of the centre of their cell (Terms & Conditions).
const HOME_MAX_KM = 5;
/// A GPS reading less exact than this cannot register a cell.
const GPS_MAX_ERROR_M = 100;

const place = (lat, lng) => typeof lat === 'number' && typeof lng === 'number' && G.inIndia(lat, lng);

/// The claimed (pending or booked) cells among [cells], by cell, with their holder for the staff member's own one.
async function claimedCells(db, cells) {
  const parents = [...new Set(cells.map(G.parent5Of))];
  const found = new Map();
  for (let i = 0; i < parents.length; i += 30) {
    const snap = await db.collection('staffAreas').where('hexParent5', 'in', parents.slice(i, i + 30)).get();
    for (const doc of snap.docs) if (doc.data().status && doc.data().status !== 'free') found.set(doc.id, doc.data());
  }
  return found;
}

/// Staff: the cell where they stand and the cells around it, each green (free) or red (taken); their own is marked.
async function hexNearby(db, staffUid, data = {}) {
  const [staff, mine] = await Promise.all([
    db.collection('fieldStaff').doc(staffUid).get().then(d => d.data()),
    db.collection('staffAreaStaff').doc(staffUid).get().then(d => d.data()),
  ]);
  if (!staff || !['pending', 'active'].includes(staff.status)) throw Error('Register as staff first.');
  if (!place(data.latitude, data.longitude)) throw Error('Turn on location. Your place must be in India.');
  const cells = G.cellsNear(data.latitude, data.longitude);
  const taken = await claimedCells(db, cells);
  const myArea = mine?.areaId ? (await db.collection('staffAreas').doc(mine.areaId).get()).data() : null;
  const status = cell => (taken.has(cell) ? (mine?.areaId === cell ? 'mine' : 'taken') : 'free');
  const [lat, lng] = G.centerOf(cells[0]);
  return {
    cellId: cells[0], code: G.codeOf(cells[0]), sizeKm: G.sizeKm(cells[0]), center: [lat, lng], status: status(cells[0]),
    homeMaxKm: HOME_MAX_KM, hasArea: Boolean(myArea && myArea.status !== 'free'), myAreaCode: myArea && myArea.status !== 'free' ? myArea.hexCode || myArea.name || '' : '',
    cells: cells.map(cell => ({cellId: cell, code: G.codeOf(cell), sizeKm: G.sizeKm(cell), status: status(cell), outline: G.outlineOf(cell)})),
  };
}

const homeText = v => (typeof v === 'string' ? v.trim().replace(/\s+/g, ' ') : '');

/// Staff: registers the cell where they stand (GPS on, inside it), if it is free, with their home pin within 5 km of the cell's centre
/// and the Terms accepted. One cell per staff member; a cell is never shared. Pending until the admin approves the staff member.
async function claimHexCell(db, staffUid, data = {}, now = Date.now()) {
  if (data.termsAccepted !== true) throw Error('Tick "I accept the Terms & Conditions" to finish.');
  if (!place(data.latitude, data.longitude)) throw Error('Turn on GPS. We need where you stand to register your cell.');
  if (data.accuracyM !== undefined && data.accuracyM !== null && !(typeof data.accuracyM === 'number' && data.accuracyM >= 0 && data.accuracyM <= GPS_MAX_ERROR_M)) {
    throw Error(`Your GPS is not exact enough (more than ${GPS_MAX_ERROR_M} m). Go to an open place and try again.`);
  }
  const cell = G.cellAt(data.latitude, data.longitude);
  if (data.cellId !== undefined && data.cellId !== cell) throw Error('You are not standing inside this cell. Go inside the cell to register it.');
  if (!place(data.homeLatitude, data.homeLongitude)) throw Error('Put the pin on your home on the map.');
  const homeAddress = homeText(data.homeAddress);
  if (homeAddress.length < 10 || homeAddress.length > 300) throw Error('Enter your home address (10 to 300 letters).');
  const center = G.centerOf(cell);
  const homeKm = Math.round(G.distanceKm([data.homeLatitude, data.homeLongitude], center) * 100) / 100;
  if (homeKm > HOME_MAX_KM) throw Error(`Your home is ${homeKm.toFixed(1)} km from the centre of this cell. Staff must live within ${HOME_MAX_KM} km of their cell's centre.`);
  const code = G.codeOf(cell);
  const sizeKm = G.sizeKm(cell);
  const outline = G.outlineOf(cell);
  const staffRef = db.collection('fieldStaff').doc(staffUid);
  const mineRef = db.collection('staffAreaStaff').doc(staffUid);
  const areaRef = db.collection('staffAreas').doc(cell);
  const holderRef = db.collection('staffAreaHolders').doc(cell);
  return db.runTransaction(async tx => {
    const [staffDoc, mineDoc, areaDoc, termsDoc] = await Promise.all([tx.get(staffRef), tx.get(mineRef), tx.get(areaRef), tx.get(settingsRef(db))]);
    const staff = staffDoc.data();
    if (!staff || !['pending', 'active'].includes(staff.status)) throw Error('Register as staff first.');
    if (await heldArea(ref => tx.get(ref), db, mineDoc.data())) throw Error('You already have a cell. One staff member has one cell.');
    const existing = areaDoc.data();
    if (existing && existing.status !== 'free') throw Error('This cell is already taken (red). Only a free (green) cell can be registered.');
    const at = Timestamp.fromMillis(now);
    const status = staff.status === 'active' ? 'booked' : 'pending';
    const town = B.label(staff.town || staff.placeName || staff.district, code);
    const name = town === code ? code : `${code} · ${town}`;
    tx.set(areaRef, {
      name, town, townKey: R.townKey(town), latitude: center[0], longitude: center[1], radiusKm: G.radiusKmOf(cell), status,
      hex: true, hexCell: cell, hexCode: code, hexSizeKm: sizeKm, hexParent5: G.parent5Of(cell), hexOutline: outline.flat(),
      createdAt: existing?.createdAt ?? at, updatedAt: at,
    });
    tx.set(holderRef, {
      staffUid, staffCode: staff.staffCode || '', staffName: staff.name || staff.displayName || '', staffPhone: staff.phone || '',
      claimedAt: at, ...(status === 'booked' ? {bookedAt: at} : {}),
    });
    tx.set(mineRef, {
      staffUid, areaId: cell, areaName: name, town, areaCode: code, termsAcceptedAt: at, termsVersion: termsDoc.data()?.updatedAt ?? null, claimedAt: at,
      homeLatitude: data.homeLatitude, homeLongitude: data.homeLongitude, homeAddress, homeDistanceKm: homeKm,
      ...(status === 'booked' ? {bookedAt: at} : {}),
    }, {merge: true});
    return {areaId: cell, code, sizeKm, status, homeDistanceKm: homeKm};
  });
}

/// The staff record changed (fieldStaff/<uid> trigger): approved -> the pending area is booked; not approved -> the area is free again.
async function onStaffStatus(db, staffUid, before, after, now = Date.now()) {
  if (!after || before?.status === after.status) return null;
  const mine = (await db.collection('staffAreaStaff').doc(staffUid).get()).data();
  if (!mine?.areaId) return null;
  const areaRef = db.collection('staffAreas').doc(mine.areaId);
  const holderRef = db.collection('staffAreaHolders').doc(mine.areaId);
  return db.runTransaction(async tx => {
    const area = (await tx.get(areaRef)).data();
    const holder = (await tx.get(holderRef)).data();
    if (!area || holder?.staffUid !== staffUid) return null;
    const at = Timestamp.fromMillis(now);
    if (after.status === 'active' && area.status === 'pending') {
      tx.update(areaRef, {status: 'booked', updatedAt: at});
      tx.update(holderRef, {bookedAt: at});
      tx.set(db.collection('staffAreaStaff').doc(staffUid), {bookedAt: at}, {merge: true});
      return 'booked';
    }
    // Not approved, or the staff ID was cancelled for good (owner, 13 Nov 2026): the cell is free again for a new staff member.
    if (after.status === 'rejected' || after.status === 'cancelled') {
      tx.update(areaRef, {status: 'free', updatedAt: at});
      tx.delete(holderRef);
      tx.set(db.collection('staffAreaStaff').doc(staffUid), {areaId: null, ...(after.status === 'cancelled' ? {cancelledAreaId: mine.areaId, cancelledAt: at} : {})}, {merge: true});
      return 'free';
    }
    return null;
  });
}

/// Admin: frees an area (the staff member then has none and may choose another).
async function freeArea(db, data, now = Date.now()) {
  if (typeof data.areaId !== 'string' || !ID.test(data.areaId)) throw Error('That area was not found.');
  const areaRef = db.collection('staffAreas').doc(data.areaId);
  const holderRef = db.collection('staffAreaHolders').doc(data.areaId);
  const holder = (await holderRef.get()).data();
  const batch = db.batch();
  batch.update(areaRef, {status: 'free', updatedAt: Timestamp.fromMillis(now)});
  batch.delete(holderRef);
  if (holder?.staffUid) batch.set(db.collection('staffAreaStaff').doc(holder.staffUid), {areaId: null}, {merge: true});
  await batch.commit();
  return {freed: true};
}

/// The shops whose place is inside an area (a band of latitude is read, then the circle is checked).
async function shopsInArea(db, area) {
  const band = area.radiusKm / 111 + 0.001;
  const found = await db.collection('shops').where('latitude', '>=', area.latitude - band).where('latitude', '<=', area.latitude + band).get();
  return found.docs.filter(doc => doc.data().active !== false && R.inside(area, doc.data().latitude, doc.data().longitude)).map(doc => ({id: doc.id, ...doc.data()}));
}

/// The offers made on an India [day] for the shops of an area: the staff member's own, and the vendors' own.
async function dayCounts(db, area, day, shops = null) {
  const inArea = new Set((shops ?? await shopsInArea(db, area)).map(s => s.id));
  const made = await db.collection('vendorOffers')
    .where('createdAt', '>=', Timestamp.fromMillis(R.dayStart(day)))
    .where('createdAt', '<=', Timestamp.fromMillis(R.dayEnd(day)))
    .get();
  let staffCount = 0, vendorCount = 0;
  const shopsWithOffer = new Set();
  for (const doc of made.docs) {
    const offer = doc.data();
    if (offer.status === 'removed' || !inArea.has(offer.shopId)) continue;
    if (offer.source === 'staff') { if (offer.areaId === area.id) staffCount++; else continue; } else vendorCount++;
    shopsWithOffer.add(offer.shopId);
  }
  return {staffCount, vendorCount, shopsWithOffer};
}

async function staffArea(db, staffUid) {
  const staff = (await db.collection('fieldStaff').doc(staffUid).get()).data();
  const mine = (await db.collection('staffAreaStaff').doc(staffUid).get()).data();
  const areaDoc = mine?.areaId ? await db.collection('staffAreas').doc(mine.areaId).get() : null;
  const holder = mine?.areaId ? (await db.collection('staffAreaHolders').doc(mine.areaId).get()).data() : null;
  const area = areaDoc?.exists && holder?.staffUid === staffUid ? areaOf(areaDoc) : null;
  return {staff, mine, area};
}

/// A staff member's work today, this week and this month: live photos, shops visited, linked vendors (and the paid ones), rate days.
/// Each period has its own targets (Admin > Staff Areas > Settings).
async function workProgress(db, staffUid, now = Date.now()) {
  const settings = await readSettings(db);
  const day = R.istDay(now);
  const month = day.slice(0, 7);
  const week = R.weekOf(day);
  const [offers, links] = await Promise.all([
    db.collection('vendorOffers').where('staffUid', '==', staffUid).get(),
    db.collection('staffLinks').where('staffUid', '==', staffUid).get(),
  ]);
  const verified = offers.docs.map(d => d.data()).filter(o => o.source === 'staff' && o.livePhotoVerified === true && o.status !== 'removed');
  const madeOn = o => R.istDay(o.createdAt?.toMillis?.() ?? 0);
  const inPeriod = {daily: d => d === day, weekly: d => d >= week && d <= day, monthly: d => d.slice(0, 7) === month};
  const rateDays = new Set(verified.map(madeOn).filter(inPeriod.weekly)).size;
  const today = verified.filter(o => madeOn(o) === day).length;
  const vendorLinks = links.docs.map(d => d.data()).filter(l => l.kind === 'vendor' && inPeriod.monthly(R.istDay(l.linkedAt?.toMillis?.() ?? 0)));
  const premium = await Promise.all(vendorLinks.map(l => db.collection('vendorPremium').doc(l.accountUid).get()));
  const paidUids = new Set(premium.filter(d => d.data()?.active === true && (d.data().endsAt?.toMillis?.() ?? 0) > now).map(d => d.id));
  const targets = {};
  for (const period of R.PERIODS) {
    const mine = verified.filter(o => inPeriod[period](madeOn(o)));
    const linked = vendorLinks.filter(l => inPeriod[period](R.istDay(l.linkedAt?.toMillis?.() ?? 0)));
    targets[period] = R.periodTargets(settings, period, {
      photos: mine.length, shops: new Set(mine.map(o => o.shopId)).size, vendors: linked.length, paidVendors: linked.filter(l => paidUids.has(l.accountUid)).length,
    });
  }
  return {
    settings, day, month, week, today, targets,
    photos: targets.monthly.photos, vendors: targets.monthly.vendors, paidVendors: targets.monthly.paidVendors, shops: targets.monthly.shops,
    rateDays: R.targetProgress(rateDays, settings.rateDaysPerWeek),
  };
}

/// The staff dashboard: my area, the monthly targets with their progress, this week's rate days, missed days this month, today's rate
/// updates, and the shops of my area with a mark on those with an offer today.
async function myToday(db, staffUid, now = Date.now()) {
  const {staff, mine, area} = await staffArea(db, staffUid);
  if (!staff) throw Error('Register as staff first.');
  const work = await workProgress(db, staffUid, now);
  const missed = mine?.month === work.month ? mine.missedThisMonth || 0 : 0;
  const base = {
    day: work.day,
    photos: work.photos, vendors: work.vendors, paidVendors: work.paidVendors, shopsVisited: work.shops, rateDays: work.rateDays, todayUpdates: work.today,
    targets: work.targets,
    missedThisMonth: missed, maxMissedDays: work.settings.maxMissedDays,
    warning: mine?.month === work.month ? mine.warning || '' : '',
  };
  if (!area) return {...base, area: null};
  const shops = await shopsInArea(db, area);
  const counts = await dayCounts(db, area, work.day, shops);
  return {
    ...base,
    area: {id: area.id, name: area.name, town: area.town, latitude: area.latitude, longitude: area.longitude, radiusKm: area.radiusKm, status: area.status},
    staffCount: counts.staffCount,
    vendorCount: counts.vendorCount,
    shops: shops.map(s => ({id: s.id, name: s.name || '', latitude: s.latitude, longitude: s.longitude, offerToday: counts.shopsWithOffer.has(s.id)})),
  };
}

/// A staff member updates a shop's rate in their area: a Today's Offer with a LIVE camera photo taken at the shop (within 100 m, real
/// GPS, sent soon after). From anywhere else it is refused and never counts. The item comes from the admin's list.
async function addStaffOffer(db, bucket, staffUid, data = {}, now = Date.now()) {
  const today = R.istDay(now);
  const safe = R.validateStaffOffer(data, today);
  const {staff, area} = await staffArea(db, staffUid);
  if (staff?.status !== 'active') throw Error('Only approved staff can add offers.');
  if (!area || area.status !== 'booked') throw Error('You need your own area first.');
  const shop = (await db.collection('shops').doc(safe.shopId).get()).data();
  if (!shop || shop.active === false) throw Error('That shop was not found.');
  if (!R.inside(area, shop.latitude, shop.longitude)) throw Error('You can add offers only for shops inside your own area.');
  const photo = data.photo || {};
  if (typeof photo.id !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(photo.id)) throw Error('Take a live photo at the shop first.');
  const problem = R.livePhotoProblem(photo, shop, now);
  if (problem) throw Error(problem);
  const path = `staffOfferPhotos/${staffUid}/${photo.id}`;
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) throw Error('Take a live photo at the shop first.');
  const [meta] = await file.getMetadata();
  const uploadedAt = Date.parse(meta.timeCreated || '') || 0;
  if (now - uploadedAt > R.MAX_PHOTO_AGE_MS + 5 * 60000) throw Error('Take a new live photo: this one is too old.');
  const item = (await db.collection('productImageLibrary').doc(safe.libraryItemId).get()).data();
  if (!item || item.active === false) throw Error('Choose the item from the list.');
  const same = await db.collection('vendorOffers').where('shopId', '==', safe.shopId).where('libraryItemId', '==', safe.libraryItemId).get();
  if (same.docs.some(d => d.data().source === 'staff' && d.data().validDate === safe.validDate && d.data().status !== 'removed')) {
    throw Error('This shop already has this item as an offer today.');
  }
  const at = Timestamp.fromMillis(now);
  const ref = db.collection('vendorOffers').doc();
  // One photo, one rate update: a photo can never be sent twice.
  await db.collection('staffOfferPhotoUses').doc(photo.id).create({staffUid, offerId: ref.id, at});
  const metres = Math.round(R.distanceKm(photo.latitude, photo.longitude, shop.latitude, shop.longitude) * 1000);
  const liveUrl = publicStorageUrl(bucket.name, path);
  await ref.set({
    source: 'staff', staffUid, staffCode: staff.staffCode || '', areaId: area.id,
    vendorId: '', shopId: safe.shopId, shopName: shop.name || '',
    title: item.name || 'Offer', details: '', libraryItemId: safe.libraryItemId,
    offerPrice: safe.offerPrice, regularPrice: safe.regularPrice, photos: [liveUrl, ...(item.imageUrl ? [item.imageUrl] : [])],
    livePhotoVerified: true, livePhoto: {path, metres, accuracy: photo.accuracy, takenAt: Timestamp.fromMillis(photo.takenAt)},
    status: 'live', validDate: safe.validDate, endsAt: Timestamp.fromMillis(R.dayEnd(safe.validDate) + 1),
    createdAt: at, updatedAt: at,
  });
  return {offerId: ref.id, validDate: safe.validDate, metres};
}

/// A staff member removes their own Today's Offer (a mistake). Vendors' own offers are never theirs to touch.
async function removeStaffOffer(db, staffUid, data = {}) {
  if (typeof data.offerId !== 'string' || !ID.test(data.offerId)) throw Error('Offer not found.');
  const ref = db.collection('vendorOffers').doc(data.offerId);
  const offer = (await ref.get()).data();
  if (!offer || offer.source !== 'staff' || offer.staffUid !== staffUid) throw Error('Offer not found.');
  await ref.delete();
  return {deleted: true};
}

const WARN_TEXT = (missed, max) => `Last chance today: you have ${missed} missed ${missed === 1 ? 'day' : 'days'} this month. Update a shop's rate with a live photo TODAY, or your staff ID stops tonight (at ${max} missed days) and your area goes to someone else.`;
const LAST_CHANCE_TITLE = 'Last chance today: update rates';

/// Every night, for yesterday: did each staff member with an area update rates (a verified live-photo rate update)? A day without is a
/// free day off while the week's allowance lasts (7 - rate days a week), else a missed day. The [maxMissedDays]-th missed day in a month
/// stops the account and frees the area. When TODAY is the last chance (one more missed day would stop the account), the staff member
/// is warned now, at the start of the day, before it is missed. Safe to run again: each area and day counts once.
/// [push] sends a notification to a staff member's phones (uid, title, body).
async function nightlyCheck(db, push, now = Date.now()) {
  const day = R.istDay(now - R.DAY_MS);
  const month = day.slice(0, 7);
  const week = R.weekOf(day);
  const settings = await readSettings(db);
  const results = [];
  const booked = (await db.collection('staffAreas').where('status', '==', 'booked').get()).docs.map(areaOf);
  for (const area of booked) {
    const holder = (await db.collection('staffAreaHolders').doc(area.id).get()).data();
    if (!holder?.staffUid) continue;
    // A day counts only when the area was booked for all of it.
    if ((holder.bookedAt?.toMillis?.() ?? now) > R.dayStart(day)) continue;
    const dayRef = db.collection('staffAreaDays').doc(`${area.id}_${day}`);
    if ((await dayRef.get()).exists) continue;
    const mine = await db.collection('vendorOffers').where('staffUid', '==', holder.staffUid).get();
    const updates = mine.docs.map(d => d.data()).filter(o => o.livePhotoVerified === true && o.status !== 'removed' && R.istDay(o.createdAt?.toMillis?.() ?? 0) === day).length;
    const counts = await dayCounts(db, area, day);
    const mineRef = db.collection('staffAreaStaff').doc(holder.staffUid);
    const record = (await mineRef.get()).data() || {};
    const offDays = record.week === week ? record.offDaysThisWeek || 0 : 0;
    let missed = record.month === month ? record.missedThisMonth || 0 : 0;
    let outcome = 'worked';
    if (updates === 0) {
      if (R.dayOff(offDays, settings.rateDaysPerWeek) === 'off') outcome = 'off';
      else { missed++; outcome = R.missedOutcome(missed, settings.maxMissedDays); }
    }
    // Today (the day after the one just counted): would a day without updates stop the account? Then warn now, before it is missed.
    const today = R.istDay(now);
    const todayMissed = today.slice(0, 7) === month ? missed : 0;
    const todayOff = R.weekOf(today) === week ? offDays + (outcome === 'off' ? 1 : 0) : 0;
    const atRisk = outcome !== 'deactivate' && R.lastChance(todayMissed, settings.maxMissedDays, todayOff, settings.rateDaysPerWeek);
    await dayRef.set({
      areaId: area.id, areaName: area.name, town: area.town, staffUid: holder.staffUid, staffCode: holder.staffCode || '', day, month, week,
      rateUpdates: updates, staffCount: counts.staffCount, vendorCount: counts.vendorCount, total: counts.staffCount + counts.vendorCount,
      worked: updates > 0, outcome, createdAt: Timestamp.fromMillis(now),
    });
    const at = Timestamp.fromMillis(now);
    const base = {month, missedThisMonth: missed, week, offDaysThisWeek: offDays + (outcome === 'off' ? 1 : 0)};
    if (outcome === 'deactivate') {
      const reason = `${missed} missed days in ${month} (the account stops at ${settings.maxMissedDays}).`;
      const batch = db.batch();
      batch.set(mineRef, {...base, areaId: null, deactivatedAt: at, deactivatedReason: reason, deactivatedAreaId: area.id, deactivatedAreaName: area.name, warning: ''}, {merge: true});
      batch.update(db.collection('fieldStaff').doc(holder.staffUid), {status: 'suspended', suspensionReason: reason, suspendedAt: at, suspendedBy: 'staff-areas', suspendedFor: 'missedDays'});
      batch.update(db.collection('staffAreas').doc(area.id), {status: 'free', updatedAt: at});
      batch.delete(db.collection('staffAreaHolders').doc(area.id));
      await batch.commit();
      await push(holder.staffUid, 'Your staff ID is stopped', `${reason} Your area is free for someone else. Contact the LOCAMARKET office.`).catch(() => {});
    } else {
      const warning = atRisk ? WARN_TEXT(todayMissed, settings.maxMissedDays) : '';
      await mineRef.set({...base, warning, lastChanceDay: atRisk ? today : '', ...(atRisk ? {warnedAt: at} : {})}, {merge: true});
      if (atRisk) await push(holder.staffUid, LAST_CHANCE_TITLE, warning).catch(() => {});
    }
    results.push({areaId: area.id, staffUid: holder.staffUid, rateUpdates: updates, outcome, missed, warned: atRisk});
  }
  return {day, results};
}

/// 5 PM India time: a second reminder to everyone whose last chance is today and who has not yet sent a verified rate update today.
async function lastChanceReminder(db, push, now = Date.now()) {
  const today = R.istDay(now);
  const due = await db.collection('staffAreaStaff').where('lastChanceDay', '==', today).get();
  const reminded = [];
  for (const doc of due.docs) {
    const mine = await db.collection('vendorOffers').where('staffUid', '==', doc.id).get();
    const updates = mine.docs.map(d => d.data()).filter(o => o.livePhotoVerified === true && o.status !== 'removed' && R.istDay(o.createdAt?.toMillis?.() ?? 0) === today).length;
    if (updates > 0) continue;
    await push(doc.id, 'Reminder: last chance today', doc.data().warning || 'Update a shop\'s rate with a live photo today, or your staff ID stops tonight.').catch(() => {});
    reminded.push(doc.id);
  }
  return {day: today, reminded};
}

/// Admin: reactivates a staff member the system deactivated, giving back their area if it is still free.
async function reactivate(db, data = {}, adminUid = '', now = Date.now()) {
  if (typeof data.staffUid !== 'string' || !ID.test(data.staffUid)) throw Error('Choose the staff member.');
  const mineRef = db.collection('staffAreaStaff').doc(data.staffUid);
  const staffRef = db.collection('fieldStaff').doc(data.staffUid);
  return db.runTransaction(async tx => {
    const mine = (await tx.get(mineRef)).data();
    const staff = (await tx.get(staffRef)).data();
    if (!mine?.deactivatedAt || staff?.status !== 'suspended') throw Error('This staff member is not deactivated.');
    const areaRef = db.collection('staffAreas').doc(mine.deactivatedAreaId || '-');
    const area = (await tx.get(areaRef)).data();
    if (!area || area.status !== 'free') throw Error('Their area is taken now, so they cannot be reactivated with it.');
    const at = Timestamp.fromMillis(now);
    tx.update(staffRef, {status: 'active', reinstatedAt: at, reinstatedBy: adminUid, suspensionReason: FieldValue.delete(), suspendedFor: FieldValue.delete()});
    tx.update(areaRef, {status: 'booked', updatedAt: at});
    tx.set(db.collection('staffAreaHolders').doc(mine.deactivatedAreaId), {
      staffUid: data.staffUid, staffCode: staff.staffCode || '', staffName: staff.name || '', staffPhone: staff.phone || '', claimedAt: at, bookedAt: at,
    });
    // A fresh start: this month's missed days are cleared, so the next miss does not deactivate them again at once.
    tx.set(mineRef, {areaId: mine.deactivatedAreaId, missedThisMonth: 0, warning: '', reactivatedAt: at, reactivatedBy: adminUid, deactivatedAt: null, deactivatedReason: '', bookedAt: at}, {merge: true});
    return {areaId: mine.deactivatedAreaId};
  });
}

/// Admin reports for a month: per staff member (area, the monthly targets and whether they are complete, rate days, missed days,
/// offers by the staff member and by the area's vendors) and per town (areas free / booked / pending, deactivated this month).
async function report(db, data = {}, now = Date.now()) {
  const month = typeof data.month === 'string' && /^\d{4}-\d{2}$/.test(data.month) ? data.month : R.istDay(now).slice(0, 7);
  const settings = await readSettings(db);
  const [areas, holders, days, staffDocs, mineDocs, links, offers] = await Promise.all([
    allAreas(db),
    db.collection('staffAreaHolders').get(),
    db.collection('staffAreaDays').where('month', '==', month).get(),
    db.collection('fieldStaff').get(),
    db.collection('staffAreaStaff').get(),
    db.collection('staffLinks').get(),
    db.collection('vendorOffers').where('source', '==', 'staff').get(),
  ]);
  const holderOf = new Map(holders.docs.map(d => [d.id, d.data()]));
  const mineOf = new Map(mineDocs.docs.map(d => [d.id, d.data()]));
  const inMonth = ms => R.istDay(ms ?? 0).slice(0, 7) === month;
  const staffRows = [];
  for (const doc of staffDocs.docs) {
    const staff = doc.data();
    const mine = mineOf.get(doc.id) || {};
    const area = areas.find(a => holderOf.get(a.id)?.staffUid === doc.id);
    const myDays = days.docs.map(d => d.data()).filter(d => d.staffUid === doc.id);
    const myLinks = links.docs.map(d => d.data()).filter(l => l.staffUid === doc.id && inMonth(l.linkedAt?.toMillis?.()));
    const vendorLinks = myLinks.filter(l => l.kind === 'vendor');
    const paid = (await Promise.all(vendorLinks.map(l => db.collection('vendorPremium').doc(l.accountUid).get()))).filter(d => d.data()?.active === true).length;
    const mineVerified = offers.docs.map(d => d.data()).filter(o => o.staffUid === doc.id && o.livePhotoVerified === true && inMonth(o.createdAt?.toMillis?.()));
    const photos = mineVerified.length;
    const shopsVisited = new Set(mineVerified.map(o => o.shopId)).size;
    const monthly = R.periodTargets(settings, 'monthly', {photos, shops: shopsVisited, vendors: vendorLinks.length, paidVendors: paid});
    staffRows.push({
      staffUid: doc.id, staffCode: staff.staffCode || '', name: staff.name || '', phone: staff.phone || '', status: staff.status || '',
      area: area?.name || mine.deactivatedAreaName || '', town: area?.town || '',
      photos, shopsVisited, vendorsLinked: vendorLinks.length, paidVendorsLinked: paid, providersLinked: myLinks.filter(l => l.kind === 'provider').length,
      monthComplete: Object.values(monthly).every(t => t.complete),
      daysWorked: myDays.filter(d => d.worked).length, staffOffers: myDays.reduce((s, d) => s + (d.staffCount || 0), 0), vendorOffers: myDays.reduce((s, d) => s + (d.vendorCount || 0), 0),
      missedDays: mine.month === month ? mine.missedThisMonth || 0 : 0,
      deactivatedAt: mine.deactivatedAt?.toMillis?.() ?? null, deactivatedReason: mine.deactivatedReason || '',
    });
  }
  const towns = new Map();
  for (const a of areas) {
    const t = towns.get(a.townKey) || {town: a.town, total: 0, free: 0, pending: 0, booked: 0, deactivatedThisMonth: 0};
    t.total++;
    t[a.status] = (t[a.status] || 0) + 1;
    towns.set(a.townKey, t);
  }
  for (const mine of mineOf.values()) {
    const at = mine.deactivatedAt?.toMillis?.();
    if (!at || !inMonth(at)) continue;
    const area = areas.find(a => a.id === mine.deactivatedAreaId);
    if (area && towns.has(area.townKey)) towns.get(area.townKey).deactivatedThisMonth++;
  }
  return {month, targets: settings, staff: staffRows, towns: [...towns.values()].sort((a, b) => a.town.localeCompare(b.town))};
}

module.exports = {
  hexNearby, claimHexCell, HOME_MAX_KM,
  previewAutoArea, claimAutoArea,
  readSettings, saveSettings, saveTown, saveArea, deleteArea, claimArea, onStaffStatus, freeArea,
  shopsInArea, dayCounts, workProgress, myToday, addStaffOffer, removeStaffOffer, nightlyCheck, lastChanceReminder, reactivate, report, WARN_TEXT,
};
