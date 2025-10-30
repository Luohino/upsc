import 'package:flutter/material.dart';
import '../../features/data/model/notification_payload.dart';
import '../../features/presentation/pages/ios_incoming_call_page.dart';
import '../../features/presentation/pages/login_page.dart';
import '../../features/presentation/pages/sign_up_page.dart';
import '../../features/presentation/pages/video_call_page.dart';
import '../../features/presentation/pages/info_page.dart';
import '../../features/presentation/pages/google_auth_page.dart';
import '../../features/presentation/pages/users_list_page_v2.dart';
import '../../features/presentation/pages/chat_page.dart';

abstract class AppRoutes {
  static const String infoPage = "/";
  static const String authenticationPage = "/auth";
  static const String googleAuthPage = "/googleAuth";
  static const String usersListPage = "/usersList";
  static const String loginPage = "/loginPage";
  static const String signUpPage = "/signUpPage";
  static const String homePage = "/homePage";
  static const String audioCallPage = "/audioCallPage";
  static const String videoCallPage = "/videoCallPage";
  static const String chatPage = "/chatPage";
  static const String iosIncomingCallPage = "/iosIncomingCallPage";
}

class AppNavigator {
  static Route<dynamic>? materialAppRoutes(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.infoPage:
        return _getMaterialPageRoute(
          widget: const InfoPage(),
          settings: settings,
        );
      case AppRoutes.authenticationPage:
        return _getMaterialPageRoute(
          widget: const LoginPage(),
          settings: settings,
        );

      case AppRoutes.googleAuthPage:
        return _getMaterialPageRoute(
          widget: const GoogleAuthPage(),
          settings: settings,
        );

      case AppRoutes.usersListPage:
        return _getMaterialPageRoute(
          widget: const UsersListPageV2(),
          settings: settings,
        );

      case AppRoutes.loginPage:
        return _getMaterialPageRoute(
          widget: const LoginPage(),
          settings: settings,
        );

      case AppRoutes.signUpPage:
        return _getMaterialPageRoute(
          widget: const SignUpPage(),
          settings: settings,
        );

      case AppRoutes.homePage:
        return _getMaterialPageRoute(
          widget: const UsersListPageV2(),
          settings: settings,
        );

      case AppRoutes.audioCallPage:
        final payload = settings.arguments as NotificationPayload;
        return _getMaterialPageRoute(
          widget: IOSIncomingCallPage(
            callerName: payload.name ?? payload.username ?? 'Unknown',
            callerImage: payload.imageUrl,
            isOutgoing: payload.callAction == CallAction.create,
            isVideo: false,
            callPayload: payload,
          ),
          settings: settings,
          transparent: true,
        );

      case AppRoutes.videoCallPage:
        return _getMaterialPageRoute(
          widget: VideoCallPage(
            payload: settings.arguments as NotificationPayload,
          ),
          settings: settings,
        );

      case AppRoutes.chatPage:
        final args = settings.arguments as Map<String, dynamic>;
        return _getMaterialPageRoute(
          widget: ChatPage(
            currentUser: args['currentUser'],
            receiverUser: args['receiverUser'],
          ),
          settings: settings,
        );

      case AppRoutes.iosIncomingCallPage:
        final args = settings.arguments as Map<String, dynamic>;
        return _getMaterialPageRoute(
          widget: IOSIncomingCallPage(
            callerName: args['callerName'] as String,
            callerImage: args['callerImage'] as String?,
            isOutgoing: args['isOutgoing'] as bool? ?? false,
            isVideo: args['isVideo'] as bool? ?? false,
            callPayload: args['callPayload'] as NotificationPayload?,
          ),
          settings: settings,
          transparent: true,
        );

      default:
        return null;
    }
  }

  static _getMaterialPageRoute({
    required Widget widget,
    required RouteSettings settings,
    bool transparent = false,
  }) {
    return PageRouteBuilder(
      opaque: !transparent,
      settings: settings,
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      pageBuilder: (context, animation, secondaryAnimation) => widget,
    );
  }
}
