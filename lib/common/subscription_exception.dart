import 'package:fl_clash/common/app_localizations.dart';

/// Thrown when subscription content is encrypted but the password is
/// missing or wrong.
class SubscriptionEncryptedException implements Exception {
  const SubscriptionEncryptedException({this.passwordWrong = false});

  final bool passwordWrong;

  @override
  String toString() => passwordWrong
      ? currentAppLocalizations.subscriptionPasswordWrongTip
      : currentAppLocalizations.subscriptionLoginPassword;
}
