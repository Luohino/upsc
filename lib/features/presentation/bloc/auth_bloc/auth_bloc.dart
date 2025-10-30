import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/common_imports.dart';
import '../../../../core/utils/fcm_helper.dart';
import '../../../data/model/user.dart';

part 'auth_event.dart';

part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  FirebaseFirestore db = FirebaseFirestore.instance;
  User? user;
  StreamSubscription? userStream;

  AuthBloc() : super(AuthInitial()) {
    on<LoginEvent>(_login);
    on<SignUpEvent>(_signUp);
    on<MultipleLoginEvent>(_handleMultipleLogin);
    on<UpdateFCMTokenEvent>(_updateFCMToken);
    on<LogoutEvent>(_logout);
  }

  FutureOr<void> _login(
    LoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(AuthLoadingState());
      var user = await getUserByUsername(event.username);
      if (user != null) {
        this.user = User.fromJson(user.data().asMap);
        this.user?.userId = user.id;
        add(UpdateFCMTokenEvent());
        await SharedPrefs.setUserDetails(jsonEncode(this.user?.toJson()));
        emit(AuthSuccessState(message: 'User log in successfully'));
      } else {
        emit(AuthFailureState(
            message: 'user not available, please sign up first'));
      }
    } on Exception catch (e) {
      showLog(e.toString());
      emit(AuthFailureState(message: 'something went wrong'));
    }
  }

  FutureOr<void> _signUp(
    SignUpEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(AuthLoadingState());
      var user = await getUserByUsername(event.user.username ?? '');
      if (user == null) {
        var ds = db.collection('user').doc();
        await ds.set(event.user.toJson());
        this.user = event.user;
        this.user?.userId = ds.id;
        add(UpdateFCMTokenEvent());
        await SharedPrefs.setUserDetails(jsonEncode(this.user?.toJson()));
        _setUpStream(db.collection('user').doc(ds.id).snapshots());
        emit(AuthSuccessState(message: 'User sign up successfully'));
      } else {
        emit(AuthFailureState(
            message: 'Username exist, please choose a different username'));
      }
    } on Exception catch (e) {
      showLog(e.toString());
      emit(AuthFailureState(message: 'something went wrong'));
    }
  }

  FutureOr<void> _handleMultipleLogin(
      MultipleLoginEvent event, Emitter<AuthState> emit) async {
    user = null;
    await SharedPrefs.remove();
    emit(AuthMultipleLoginState());
  }

  FutureOr<void> _updateFCMToken(
      UpdateFCMTokenEvent event, Emitter<AuthState> emit) async {
    try {
      // CRITICAL: Wait for FCM token if not available yet
      String? token = FCMHelper.fcmToken;
      if (token == null || token.isEmpty) {
        showLog('⏳ [Auth] FCM token not ready, waiting...');
        // Wait up to 5 seconds for token
        for (int i = 0; i < 10; i++) {
          await Future.delayed(Duration(milliseconds: 500));
          token = FCMHelper.fcmToken;
          if (token != null && token.isNotEmpty) {
            showLog('✅ [Auth] FCM token obtained: ${token.substring(0, 20)}...');
            break;
          }
        }
      }
      
      user?.fcmToken = token;

      // Check if user document exists, create if not
      final userDocRef = db.collection('users').doc(user?.userId);
      final userDoc = await userDocRef.get();

      if (userDoc.exists) {
        // Update existing document with both fields
        final updateData = <String, dynamic>{
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        };
        
        if (token != null && token.isNotEmpty) {
          updateData['fcmToken'] = token;
          updateData['deviceTokens'] = FieldValue.arrayUnion([token]);
        }
        
        await userDocRef.update(updateData);
        showLog('✅ FCM token updated for user: ${user?.userId}');
      } else {
        // Document doesn't exist, create it
        final createData = {
          'uid': user?.userId,
          'name': user?.name,
          'username': user?.username,
          'photoUrl': user?.imageUrl,
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
          'deviceTokens': token != null && token.isNotEmpty ? [token] : [],
        };
        
        // Only set fcmToken if we have a valid token
        if (token != null && token.isNotEmpty) {
          createData['fcmToken'] = token;
          showLog('✅ User document created with FCM token: ${token.substring(0, 20)}...');
        } else {
          createData['fcmToken'] = null;
          showLog('⚠️ User document created WITHOUT FCM token (will be updated later)');
        }
        
        await userDocRef.set(createData);
      }

      _setUpStream(db.collection('users').doc(user?.userId).snapshots());
    } catch (e) {
      showLog('❌ Error updating FCM token: $e');
    }
  }

  FutureOr<void> _logout(
    LogoutEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final userDocRef = db.collection('users').doc(user?.userId);
      final userDoc = await userDocRef.get();
      if (userDoc.exists) {
        await userDocRef.update({
          'fcmToken': null,
          'isOnline': false,
          'lastSeen': FieldValue.serverTimestamp()
        });
      }
    } catch (e) {
      showLog('Error during logout FCM cleanup: $e');
    }
    user = null;
    SharedPrefs.remove();
  }

  Future<QueryDocumentSnapshot?> getUserByUsername(String username) async {
    List<QueryDocumentSnapshot> list = (await db
            .collection('user')
            .where('username', isEqualTo: username)
            .get())
        .docs;
    if (list.isNotEmpty) {
      return list.firstWhere((element) =>
          User.fromJson(element.data().asMap).username == username);
    }
    return null;
  }

  void _setUpStream(Stream<DocumentSnapshot> stream) {
    userStream = stream.listen((event) {
      final data = event.data();
      if (data == null) {
        showLog('⚠️ User document data is null, skipping FCM check');
        return;
      }

      String? fcmToken = User.fromJson(data as Map<String, dynamic>).fcmToken;
      if (fcmToken != null && FCMHelper.fcmToken != fcmToken) {
        add(MultipleLoginEvent());
      }
    });
  }
}
