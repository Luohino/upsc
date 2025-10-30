/**
 * Firebase Cloud Function to auto-heal missing FCM tokens
 * 
 * This function automatically removes null FCM tokens from Firestore
 * so the migration on app startup can regenerate them properly.
 * 
 * Deploy: firebase deploy --only functions
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

/**
 * Triggered whenever a user document is updated
 * Automatically fixes null/invalid FCM tokens
 */
exports.autoHealFCMTokens = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    const after = change.after.data();
    const before = change.before.data();
    
    // If user just came online with a null FCM token, clear it
    // This forces the app to regenerate a valid token on next startup
    if (after.isOnline === true && after.fcmToken === null) {
      console.log(`🧹 User ${context.params.userId} came online with null FCM token, clearing for regeneration`);
      
      // Remove the null fcmToken and empty deviceTokens array
      await change.after.ref.update({
        fcmToken: admin.firestore.FieldValue.delete(),
        deviceTokens: admin.firestore.FieldValue.delete(),
      });
      
      console.log(`✅ Cleared null FCM token for user ${context.params.userId}`);
    }
    
    // If FCM token changed from valid to null (logout scenario), keep it
    // Migration will handle regeneration on next login
    if (before.fcmToken !== null && after.fcmToken === null) {
      console.log(`📝 User ${context.params.userId} FCM token set to null (logout/uninstall)`);
    }
    
    return null;
  });

/**
 * One-time callable function to fix all existing users with null FCM tokens
 * Call from Firebase Console or using Admin SDK
 */
exports.healAllNullFCMTokens = functions.https.onCall(async (data, context) => {
  // Optional: Add authentication check
  // if (!context.auth) {
  //   throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  // }
  
  console.log('🔧 Starting batch FCM token healing...');
  
  const usersRef = admin.firestore().collection('users');
  const snapshot = await usersRef.where('fcmToken', '==', null).get();
  
  const batch = admin.firestore().batch();
  let count = 0;
  
  snapshot.forEach((doc) => {
    console.log(`🧹 Healing user: ${doc.id}`);
    batch.update(doc.ref, {
      fcmToken: admin.firestore.FieldValue.delete(),
      deviceTokens: admin.firestore.FieldValue.delete(),
    });
    count++;
  });
  
  await batch.commit();
  
  console.log(`✅ Healed ${count} users with null FCM tokens`);
  
  return {
    success: true,
    usersHealed: count,
    message: `Successfully healed ${count} users. They will regenerate tokens on next app open.`
  };
});
