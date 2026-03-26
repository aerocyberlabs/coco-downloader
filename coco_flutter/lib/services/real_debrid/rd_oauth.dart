import 'dart:async';

import 'package:dio/dio.dart';

/// The public OAuth client ID for Real-Debrid open-source applications.
///
/// Mirrors `PUBLIC_CLIENT_ID` in `rd_oauth.py`.
const String rdPublicClientId = 'X5GDLENQHZ';

const String _oauthBase = 'https://api.real-debrid.com/oauth/v2';

/// Shared Dio instance for OAuth calls (no auth header needed).
final _oauthDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ),
);

// ---------------------------------------------------------------------------
// OAuth device flow helpers
// ---------------------------------------------------------------------------

/// GET /oauth/v2/device/code – start the device-code OAuth flow.
///
/// Returns a map with at least:
/// - `device_code` – code to pass to [pollCredentials]
/// - `user_code` – short code the user types at the verification URL
/// - `verification_url` – URL to open in a browser
/// - `expires_in` – seconds until expiry
/// - `interval` – recommended polling interval in seconds
Future<Map<String, dynamic>> deviceCode() async {
  final resp = await _oauthDio.get<dynamic>(
    '$_oauthBase/device/code',
    queryParameters: {
      'client_id': rdPublicClientId,
      'new_credentials': 'yes',
    },
  );
  if (resp.statusCode != 200) {
    throw Exception('device/code failed: HTTP ${resp.statusCode}');
  }
  final body = resp.data;
  if (body is Map<String, dynamic>) return body;
  throw const FormatException('Unexpected response format from device/code');
}

/// GET /oauth/v2/device/credentials – poll until the user authorises the app.
///
/// [code] is the `device_code` value returned by [deviceCode].
/// [interval] is the polling interval in seconds (default: 5).
/// [timeout] is the maximum number of seconds to wait (default: 120).
///
/// Returns the credentials map (containing `client_id` and `client_secret`)
/// when the user approves, or throws [TimeoutException] on timeout.
Future<Map<String, dynamic>> pollCredentials(
  String code, {
  int interval = 5,
  int timeout = 120,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeout));
  final pollInterval = Duration(seconds: interval < 2 ? 2 : interval);
  String? lastError;

  while (DateTime.now().isBefore(deadline)) {
    try {
      final resp = await _oauthDio.get<dynamic>(
        '$_oauthBase/device/credentials',
        queryParameters: {
          'client_id': rdPublicClientId,
          'code': code,
        },
        options: Options(validateStatus: (_) => true),
      );
      if (resp.statusCode == 200) {
        final body = resp.data;
        if (body is Map<String, dynamic>) return body;
        throw const FormatException(
          'Unexpected response format from device/credentials',
        );
      }
      lastError = resp.data?.toString() ?? 'HTTP ${resp.statusCode}';
    } catch (e) {
      lastError = e.toString();
    }
    await Future<void>.delayed(pollInterval);
  }

  throw TimeoutException(
    'Timeout waiting for Real-Debrid credentials: $lastError',
    Duration(seconds: timeout),
  );
}

/// POST /oauth/v2/token – exchange the device code for access/refresh tokens.
///
/// [clientId] and [clientSecret] come from [pollCredentials].
/// [code] is the original `device_code` value from [deviceCode].
///
/// Returns a map containing `access_token`, `refresh_token`, and `expires_in`.
Future<Map<String, dynamic>> exchangeToken(
  String clientId,
  String clientSecret,
  String code,
) async {
  final resp = await _oauthDio.post<dynamic>(
    '$_oauthBase/token',
    data: FormData.fromMap({
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'grant_type': 'http://oauth.net/grant_type/device/1.0',
    }),
  );
  if (resp.statusCode != 200) {
    throw Exception('token exchange failed: HTTP ${resp.statusCode}');
  }
  final body = resp.data;
  if (body is Map<String, dynamic>) return body;
  throw const FormatException('Unexpected response format from /token');
}

/// POST /oauth/v2/token – use a refresh token to obtain a new access token.
///
/// Mirrors Python `refresh_access_token`.  The RD API reuses the same
/// `/token` endpoint with `grant_type=http://oauth.net/grant_type/device/1.0`
/// and the refresh token passed as `code`.
///
/// Returns a map containing at minimum `access_token` and `expires_in`.
Future<Map<String, dynamic>> refreshAccessToken(
  String clientId,
  String clientSecret,
  String refreshToken,
) async {
  final resp = await _oauthDio.post<dynamic>(
    '$_oauthBase/token',
    data: FormData.fromMap({
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': refreshToken,
      'grant_type': 'http://oauth.net/grant_type/device/1.0',
    }),
  );
  if (resp.statusCode != 200) {
    throw Exception('token refresh failed: HTTP ${resp.statusCode}');
  }
  final body = resp.data;
  if (body is Map<String, dynamic>) return body;
  throw const FormatException('Unexpected response format from /token (refresh)');
}
