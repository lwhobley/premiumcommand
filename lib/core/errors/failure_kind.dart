import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// How a failure should be handled. Only [offline] writes are safe to queue and retry later.
enum FailureKind {
  /// No connection, or the server could not be reached. Safe to retry.
  offline,

  /// Another person changed the record first. Must be reviewed, never overwritten.
  conflict,

  /// The database refused the action for this user.
  permission,

  /// The action broke a business rule (for example, a skipped lifecycle step).
  rule,

  /// Anything else.
  unknown,
}

FailureKind classifyFailure(Object error) {
  if (isNetworkError(error)) return FailureKind.offline;
  if (error is PostgrestException) {
    switch (error.code) {
      case '40001':
        return FailureKind.conflict;
      case '42501':
        return FailureKind.permission;
      case 'P0002':
      case '23505':
        return FailureKind.rule;
      default:
        return FailureKind.rule;
    }
  }
  return FailureKind.unknown;
}

bool isNetworkError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('ClientException') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable');
}

/// Plain-language message for the user. Raw database text is only shown for rule failures.
String friendlyMessage(Object error) {
  switch (classifyFailure(error)) {
    case FailureKind.offline:
      return "You appear to be offline. The change is saved on this device and will sync when you're connected.";
    case FailureKind.conflict:
      return 'Someone else changed this first. Refresh to see the latest, then try again.';
    case FailureKind.permission:
      return "You don't have permission to do that.";
    case FailureKind.rule:
      return error is PostgrestException ? error.message : 'That change is not allowed right now.';
    case FailureKind.unknown:
      return 'Something went wrong. Please try again.';
  }
}
