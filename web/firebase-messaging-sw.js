/* Firebase Hosting supplies public client configuration; no server credentials. */
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');
firebase.messaging().onBackgroundMessage(() => {
  // FCM displays notification payloads automatically; avoid duplicate alerts.
  // Data-only background work can be added here without accessing Flutter UI.
});
// Notification payloads are displayed by FCM automatically in the background.
