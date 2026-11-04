'use strict';
// Wholesale offers: the pure rules of one offer the administrator adds, no database.
const MAX_PRICE = 10000000;

const text = value => (typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '');

/// What the administrator may save. validUntil is milliseconds; the app sends the end of the chosen day.
function validateWholesale(data, now) {
  const name = text(data.name);
  if (name.length < 2 || name.length > 80) throw new Error('Enter the item name (2-80 characters).');
  if (typeof data.photoUrl !== 'string' || !/^https:\/\//.test(data.photoUrl) || data.photoUrl.length > 2000) throw new Error('Add a photo.');
  if (typeof data.price !== 'number' || !Number.isFinite(data.price) || data.price <= 0 || data.price > MAX_PRICE) throw new Error('Enter a valid wholesale price.');
  const minQuantity = text(data.minQuantity);
  if (minQuantity.length < 1 || minQuantity.length > 40) throw new Error('Enter the minimum quantity, for example 10 kg.');
  if (!Number.isInteger(data.validUntil) || data.validUntil <= now) throw new Error('Choose a validity date from today on.');
  const wholesaler = text(data.wholesaler);
  if (wholesaler.length < 2 || wholesaler.length > 80) throw new Error('Enter the wholesaler name.');
  const phone = text(data.phone).replace(/[\s-]/g, '');
  if (!/^\+?[0-9]{10,13}$/.test(phone)) throw new Error('Enter a valid contact number.');
  return {name, photoUrl: data.photoUrl, price: data.price, minQuantity, validUntil: data.validUntil, wholesaler, phone};
}

module.exports = {validateWholesale};
