importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyCsBQkZb7QtRc6LBc_s_ecJQufyisa3VaA",
  authDomain: "fir-d9456.firebaseapp.com",
  projectId: "fir-d9456",
  storageBucket: "fir-d9456.firebasestorage.app",
  messagingSenderId: "832519778099",
  appId: "1:832519778099:web:04f24c13a217f1697d1846",
  measurementId: "G-KSMPPRK8B6"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((message) => {
  console.log("onBackgroundMessage", message);
});
