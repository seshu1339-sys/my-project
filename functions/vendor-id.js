'use strict';
// Vendor IDs: VEN-<CITY>-<PIN>-<NNN>, e.g. VEN-NRPM-116-325.
//   CITY  four-letter town code from the admin's city-code table (settings/cityCodes), e.g. Narsipatnam = NRPM
//   PIN   the last three digits of the shop's pincode
//   NNN   a three-digit number, unique for that CITY-PIN (reserved in _vendorCodes so two vendors never share an ID)
// The ID is made once, when the vendor first applies, and stays the vendor's ID for good (vendorCode on the application and the
// vendor record). lib/domain/vendor_ids.dart has the same default table and rules for the admin screen.
const {officesForPincode, placeForPincode} = require('./places');

const DEFAULT_CITY_CODES = [
  {town: 'Narsipatnam', code: 'NRPM', pincodes: ''},
  {town: 'Tuni', code: 'TUNI', pincodes: ''},
  {town: 'Rajahmundry', code: 'RAJH', pincodes: ''},
];

const clean = value => String(value || '').trim().toLowerCase().replace(/\s+/g, ' ');
const pincodeList = value => String(value || '').split(/[^0-9]+/).filter(p => /^\d{6}$/.test(p));

/// The city-code table: the admin's rows (settings/cityCodes.rows) when there are any valid ones, else the built-in three.
function cityCodeRows(settings = {}) {
  const rows = Array.isArray(settings.rows) ? settings.rows : [];
  const valid = rows
    .map(row => ({town: String(row?.town || '').trim(), code: String(row?.code || '').trim().toUpperCase(), pincodes: String(row?.pincodes || '')}))
    .filter(row => row.town && /^[A-Z]{4}$/.test(row.code));
  return valid.length ? valid : DEFAULT_CITY_CODES;
}

/// Four letters from a town name when the table has no code for it (e.g. Anakapalle -> ANAK), padded with X. For an office named
/// like "Krishna Bazar (Narsipatnam)" the town in brackets is used.
function autoCityCode(town) {
  const bracket = String(town || '').match(/\(([^)]+)\)/);
  const letters = String(bracket ? bracket[1] : town || '').toUpperCase().replace(/[^A-Z]/g, '');
  return (letters + 'XXXX').slice(0, 4);
}

/// Whether a place name contains a town name as whole words: "Krishna Bazar (Narsipatnam)" contains "Narsipatnam".
const words = value => ` ${clean(value).replace(/[^a-z0-9]+/g, ' ').trim()} `;
const containsTown = (name, town) => words(town).trim() !== '' && words(name).includes(words(town));

/// The city code for a pincode: a table row that lists the pincode, else the row named like the pincode's town, else a row named
/// like any post office of that pincode (Tuni's offices are filed under another town in the directory), else a row whose town is part
/// of the pincode's town or office names ("Krishna Bazar (Narsipatnam)"), else four letters of the pincode's town ({auto: true}, so
/// the admin can see it is not from the table).
function cityCodeFor(pincode, rows = DEFAULT_CITY_CODES) {
  const pin = String(pincode || '').trim();
  const byPin = rows.find(row => pincodeList(row.pincodes).includes(pin));
  if (byPin) return {code: byPin.code, town: byPin.town, auto: false};
  const town = placeForPincode(pin).town || '';
  const byTown = rows.find(row => clean(row.town) === clean(town));
  if (byTown) return {code: byTown.code, town: byTown.town, auto: false};
  const offices = officesForPincode(pin).map(clean);
  const byOffice = rows.find(row => offices.includes(clean(row.town)));
  if (byOffice) return {code: byOffice.code, town: byOffice.town, auto: false};
  const names = [town, ...officesForPincode(pin)];
  const byPart = rows.find(row => names.some(name => containsTown(name, row.town)));
  if (byPart) return {code: byPart.code, town: byPart.town, auto: false};
  return {code: autoCityCode(town || 'XXXX'), town, auto: true};
}

/// "VEN-NRPM-116" for a pincode.
function vendorCodePrefix(pincode, rows) {
  const pin = String(pincode || '').trim();
  const last3 = /^\d{6}$/.test(pin) ? pin.slice(-3) : '000';
  return `VEN-${cityCodeFor(pin, rows).code}-${last3}`;
}

const VENDOR_CODE = /^VEN-[A-Z]{4}-\d{3}-\d{3}$/;

/// Reserves a new, unused vendor ID with the given prefix and returns it. Each ID is a document in _vendorCodes (server only), created
/// inside a transaction, so the same ID can never be handed out twice. Tries random numbers first (IDs do not reveal how many vendors
/// there are), then every number in order.
async function reserveVendorCode(db, prefix, owner, random = Math.random) {
  const tryNumber = async n => {
    const code = `${prefix}-${String(n).padStart(3, '0')}`;
    const ref = db.collection('_vendorCodes').doc(code);
    return db.runTransaction(async tx => {
      if ((await tx.get(ref)).exists) return null;
      tx.create(ref, {owner, createdAt: new Date()});
      return code;
    });
  };
  for (let attempt = 0; attempt < 40; attempt++) {
    const code = await tryNumber(100 + Math.floor(random() * 900));
    if (code) return code;
  }
  for (let n = 0; n < 1000; n++) {
    const code = await tryNumber(n);
    if (code) return code;
  }
  throw new Error(`Every vendor ID for ${prefix} is taken.`);
}

/// The vendor ID for an application: the one it already has when it still fits its pincode, else a newly reserved one.
async function vendorCodeFor(db, {pincode, existing, owner}) {
  const rows = cityCodeRows((await db.collection('settings').doc('cityCodes').get()).data() || {});
  const prefix = vendorCodePrefix(pincode, rows);
  if (VENDOR_CODE.test(existing || '') && existing.startsWith(prefix + '-')) return existing;
  return reserveVendorCode(db, prefix, owner);
}

module.exports = {DEFAULT_CITY_CODES, cityCodeRows, autoCityCode, cityCodeFor, vendorCodePrefix, reserveVendorCode, vendorCodeFor, VENDOR_CODE};
