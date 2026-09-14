/* Firebase Hosting supplies public client configuration; no server credentials. */
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');
firebase.messaging();
// Notification payloads are displayed by FCM automatically in the background.
