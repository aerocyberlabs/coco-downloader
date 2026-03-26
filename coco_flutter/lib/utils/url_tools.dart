/// URL parsing and filename extraction utilities.
///
/// Dart equivalents of the Python helpers in [utils/urltools.py].
library;

/// Attempts to derive a sensible filename from [url].
///
/// Strategy:
/// 1. Parse the URL and take the last path segment.
/// 2. Percent-decode the segment.
/// 3. Fall back to the raw [url] string if nothing useful can be extracted.
///
/// Mirrors `guess_name_from_link(link)` from [utils/urltools.py].
///
/// Example:
/// ```dart
/// guessNameFromLink('https://example.com/files/my%20movie.mkv');
/// // -> 'my movie.mkv'
/// guessNameFromLink('https://example.com/');
/// // -> 'https://example.com/'   (fallback)
/// ```
String guessNameFromLink(String url) {
  if (url.isEmpty) return url;
  try {
    final uri = Uri.parse(url);
    // pathSegments already percent-decodes each segment.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      return segments.last;
    }
  } catch (_) {
    // Fall through to raw-URL fallback.
  }
  return url;
}

/// Extracts the filename from a `Content-Disposition` header value.
///
/// Supports:
/// - `filename="foo.zip"` (RFC 2183)
/// - `filename*=UTF-8''foo%20bar.zip` (RFC 5987 extended notation)
///
/// The RFC 5987 form takes precedence when both are present.
/// Returns `null` when no filename directive is found.
///
/// Example:
/// ```dart
/// parseContentDisposition(
///   "attachment; filename*=UTF-8''my%20file.zip; filename=\"my file.zip\"",
/// );
/// // -> 'my file.zip'
/// ```
String? parseContentDisposition(String header) {
  if (header.isEmpty) return null;

  String? plain;
  String? extended;

  // Split on ';' and inspect each parameter.
  for (final part in header.split(';')) {
    final trimmed = part.trim();

    // RFC 5987: filename*=charset'language'encoded-value
    if (_startsWithCi(trimmed, "filename*=")) {
      final value = trimmed.substring("filename*=".length).trim();
      // Expected format: charset'language'encoded-value
      final apostropheIdx = value.indexOf("'");
      if (apostropheIdx >= 0) {
        final rest = value.substring(apostropheIdx + 1);
        final secondApos = rest.indexOf("'");
        if (secondApos >= 0) {
          final encoded = rest.substring(secondApos + 1);
          extended = Uri.decodeComponent(encoded);
        }
      } else {
        // No charset prefix — treat as percent-encoded plain string.
        try {
          extended = Uri.decodeComponent(value);
        } catch (_) {
          extended = value;
        }
      }
      continue;
    }

    // RFC 2183: filename="value" or filename=value
    if (_startsWithCi(trimmed, "filename=")) {
      var value = trimmed.substring("filename=".length).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      plain = value;
    }
  }

  // RFC 5987 value wins when present.
  final result = extended ?? plain;
  if (result == null || result.isEmpty) return null;
  return result;
}

bool _startsWithCi(String s, String prefix) =>
    s.toLowerCase().startsWith(prefix.toLowerCase());
