import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Proper connectivity check: first the OS-level radio state (fast), then a
/// real DNS lookup so we don't claim "online" when connected to a Wi-Fi with
/// no actual internet.
class NetworkInfo {
  NetworkInfo([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return false;
    }
    return _hasInternet();
  }

  /// Stream you can listen to for live online/offline changes.
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.asyncMap((results) async {
        if (results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none)) {
          return false;
        }
        return _hasInternet();
      });

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
