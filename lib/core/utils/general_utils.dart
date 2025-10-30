import 'dart:developer' as dev;

import 'common_imports.dart';

void showLog(String message) {
  print(message);
  dev.log(message);
}

void dismissFocus() async {
  FocusScope.of(AppConstants.navigatorContext).unfocus();
}
