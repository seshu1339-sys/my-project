// Makes the three per-app privacy policy pages from the one policy, web/privacy-policy.html:
//   web/privacy/index.html          locamarket.in/privacy          Loca Market (customers, in.locamarket.locamark)
//   web/privacy-vendor/index.html   locamarket.in/privacy-vendor   V Loca Market (shop owners and service providers)
//   web/privacy-staff/index.html    locamarket.in/privacy-staff    S Loca Market (field staff)
// Each is the full policy with the app's own name, package and a short "this app" summary at the top, so the Play listing of each
// app links to a page about that app. A folder with index.html works on Hostinger without touching .htaccess, and firebase.json
// rewrites the same paths. Run after changing web/privacy-policy.html:  node scripts/build-privacy-pages.cjs
// (test/privacy_policy_test.dart fails when the pages are out of date.)
'use strict';
const fs = require('fs');
const path = require('path');

const web = path.join(__dirname, '..', 'web');

const apps = [
  {
    dir: 'privacy',
    app: 'Loca Market',
    pkg: 'in.locamarket.locamark',
    who: 'customers',
    named: 'Local Market',
    summary: [
      'Your email address and name for your account, and the language you choose.',
      'The town, pincode and address you choose and, only if you allow it, your device location, to show shops, offers and how far each shop is, and the road to a shop.',
      'Your orders, wishlist, reviews and complaints.',
      'A notification token and your area if you turn notifications on, and whether a notification was opened.',
      'How the app is used (screens, buttons, searches, calls and directions to shops, as daily counts), app errors and start speed.',
    ],
  },
  {
    dir: 'privacy-vendor',
    app: 'V Loca Market',
    pkg: 'in.locamarket.vendor',
    who: 'shop owners and service providers',
    named: 'V Local Market',
    summary: [
      'Your verified email address, your name and mobile number.',
      "Your shop's (or, for a service provider, your) GPS location when you register; it becomes the shop address customers see.",
      'Your shop or service photos, which our team checks before customers see them (a photo may be checked with Google Cloud Vision).',
      'Your shop details, items and prices, or your service and charge per hour. Customers see your shop or service name, photo, address, location, phone number and prices.',
      'Your own numbers (calls, WhatsApp messages and directions to your shop), how the app is used (daily counts), app errors and start speed.',
    ],
  },
  {
    dir: 'privacy-staff',
    app: 'S Loca Market',
    pkg: 'in.locamarket.staff',
    who: 'LocaMarket field staff',
    named: 'S Local Market',
    summary: [
      'Your verified email address, your name, mobile number and your photo.',
      'Your GPS location when you register (your Staff ID is made from its pincode) and where you add a shop or service provider.',
      'The shops and service providers you add: their details, location and photos, which customers see once approved.',
      'Your work numbers (what you added, and the calls, WhatsApp messages and directions to the shops you added), how the app is used (daily counts), app errors and start speed.',
    ],
  },
];

/// The page for [a] from the policy [html].
function pageFor(html, a) {
  const replaceOnce = (text, from, to) => {
    if (!text.includes(from)) throw new Error(`${a.dir}: the policy no longer contains ${JSON.stringify(from.slice(0, 60))}`);
    return text.replace(from, to);
  };
  let out = html;
  out = out.replace(/<title>[^<]*<\/title>/, `<title>Privacy Policy | ${a.app}</title>`);
  out = out.replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="How ${a.app} (${a.pkg}), the LocaMarket app for ${a.who}, collects, uses and protects your information.">`);
  out = out.replace(/<link rel="canonical"[^>]*>\n?/, '');
  out = replaceOnce(out, '<link rel="icon" href="/favicon.png">', `<link rel="icon" href="/favicon.png">\n<link rel="canonical" href="https://locamarket.in/${a.dir}">`);
  out = replaceOnce(out, '<h1>Privacy Policy</h1>', `<h1>Privacy Policy &ndash; ${a.app}</h1>`);
  const box = [
    '  <div class="box">',
    `    <strong>This page is for the ${a.app} app</strong> (Google Play package <code>${a.pkg}</code>), the LocaMarket app for ${a.who}. In the policy below it is called <strong>${a.named}</strong>. The policy covers all LocaMarket apps and the website the same way.`,
    `    <p style="margin:10px 0 4px"><strong>What ${a.app} collects:</strong></p>`,
    '    <ul>',
    ...a.summary.map(s => `      <li>${s}</li>`),
    '    </ul>',
    '    <p class="muted">We do not sell your information and do not use the advertising ID. You can ask us to delete your account and data: <a href="/delete-account">how to delete</a>.</p>',
    '  </div>',
    '',
  ].join('\n');
  // the box goes right after the PDF / back links, before the policy's own introduction
  out = replaceOnce(out, '  <p>This policy explains what information Local Market collects', `${box}  <p>This policy explains what information Local Market collects`);
  // the same line endings as the policy file
  return out.replace(/\r?\n/g, html.includes('\r\n') ? '\r\n' : '\n');
}

const html = fs.readFileSync(path.join(web, 'privacy-policy.html'), 'utf8');
for (const a of apps) {
  fs.mkdirSync(path.join(web, a.dir), { recursive: true });
  fs.writeFileSync(path.join(web, a.dir, 'index.html'), pageFor(html, a));
  console.log(`web/${a.dir}/index.html  (${a.app})`);
}
module.exports = { apps, pageFor };

// /delete-account is the same page as web/delete-account.html, also as a folder so Hostinger serves it at the clean address.
fs.mkdirSync(path.join(web, 'delete-account'), { recursive: true });
fs.copyFileSync(path.join(web, 'delete-account.html'), path.join(web, 'delete-account', 'index.html'));
console.log('web/delete-account/index.html');
