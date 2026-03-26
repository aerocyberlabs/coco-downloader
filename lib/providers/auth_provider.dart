/// Authentication state management via Riverpod.
///
/// Mirrors the token-storage and OAuth device-code flow managed by the Python
/// config.py / rd_oauth.py modules. The [AuthNotifier] keeps a single
/// [AuthState] snapshot that widgets can observe for authenticated status and
/// in-progress OAuth.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/config_service.dart';
import 'config_provider.dart';

// ---------------------------------------------------------------------------
// AuthState
// ---------------------------------------------------------------------------

/// Immutable snapshot of authentication status.
class AuthState {
  const AuthState({
    this.token,
    this.isAuthenticated = false,
    this.isOAuthInProgress = false,
  });

  /// The Real-Debrid API token, or null when not authenticated.
  final String? token;

  /// True when a non-empty token is available.
  final bool isAuthenticated;

  /// True while the OAuth device-code flow is awaiting user authorisation.
  final bool isOAuthInProgress;

  AuthState copyWith({
    String? token,
    bool? isAuthenticated,
    bool? isOAuthInProgress,
    bool clearToken = false,
  }) {
    return AuthState(
      token: clearToken ? null : (token ?? this.token),
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isOAuthInProgress: isOAuthInProgress ?? this.isOAuthInProgress,
    );
  }

  @override
  String toString() {
    return 'AuthState('
        'isAuthenticated: $isAuthenticated, '
        'isOAuthInProgress: $isOAuthInProgress'
        ')';
  }
}

// ---------------------------------------------------------------------------
// OAuthCredentials
// ---------------------------------------------------------------------------

/// Credentials obtained at the end of the OAuth device-code flow.
class OAuthCredentials {
  const OAuthCredentials({
    required this.clientId,
    required this.clientSecret,
    required this.accessToken,
    required this.refreshToken,
  });

  final String clientId;
  final String clientSecret;
  final String accessToken;
  final String refreshToken;
}

// ---------------------------------------------------------------------------
// AuthNotifier
// ---------------------------------------------------------------------------

/// Manages the authentication lifecycle: token storage, keyring integration,
/// and the OAuth device-code handshake.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState()) {
    _initFromConfig();
  }

  final Ref _ref;

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Hydrate the auth state from the already-loaded config (and keyring).
  void _initFromConfig() {
    final cfg = _ref.read(configProvider);
    final token = cfg.token;
    if (token != null && token.isNotEmpty) {
      state = AuthState(token: token, isAuthenticated: true);
      return;
    }

    // If the config says the token is in the keyring, read it asynchronously.
    if (cfg.useKeyring) {
      _loadTokenFromKeyring();
    }
  }

  Future<void> _loadTokenFromKeyring() async {
    try {
      final tok = await configService.loadTokenFromKeyring();
      if (tok != null && tok.isNotEmpty) {
        state = AuthState(token: tok, isAuthenticated: true);
      }
    } catch (_) {
      // Keyring unavailable – silently ignore.
    }
  }

  // -------------------------------------------------------------------------
  // Token management
  // -------------------------------------------------------------------------

  /// Store [token] and mark as authenticated.
  ///
  /// When [remember] is true the token is persisted either to the keyring
  /// (when available) or directly in the config JSON.
  Future<void> setToken(String token, {bool remember = false}) async {
    state = AuthState(token: token, isAuthenticated: true);

    if (!remember) return;

    final notifier = _ref.read(configProvider.notifier);

    if (configService.keyringAvailable()) {
      try {
        await configService.saveTokenToKeyring(token);
        await notifier.updateConfig(
          (c) => c.copyWith(useKeyring: true, clearToken: true),
        );
      } catch (_) {
        // Keyring write failed – fall back to config-file storage.
        await notifier.updateConfig(
          (c) => c.copyWith(token: token, useKeyring: false),
        );
      }
    } else {
      await notifier.updateConfig(
        (c) => c.copyWith(token: token, useKeyring: false),
      );
    }
  }

  /// Remove the stored token from both the state, config, and the keyring.
  Future<void> clearToken() async {
    state = const AuthState();

    final notifier = _ref.read(configProvider.notifier);
    await notifier.updateConfig(
      (c) => c.copyWith(clearToken: true, useKeyring: false),
    );

    try {
      await configService.deleteTokenFromKeyring();
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // OAuth device-code flow
  // -------------------------------------------------------------------------

  /// Signal that an OAuth flow has started.
  void startOAuth() {
    state = state.copyWith(isOAuthInProgress: true);
  }

  /// Finalise the OAuth flow with [credentials] obtained from the device-code
  /// endpoint. Persists all OAuth tokens to config and updates auth state.
  Future<void> completeOAuth(OAuthCredentials credentials) async {
    final token = credentials.accessToken;
    state = AuthState(token: token, isAuthenticated: true);

    await _ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            rdOauthClientId: credentials.clientId,
            rdOauthClientSecret: credentials.clientSecret,
            rdAccessToken: credentials.accessToken,
            rdRefreshToken: credentials.refreshToken,
            // Treat the access token as the working API token.
            token: token,
            useKeyring: false,
          ),
        );
  }

  /// Cancel an in-progress OAuth flow.
  void cancelOAuth() {
    state = state.copyWith(isOAuthInProgress: false);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global authentication state provider.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
