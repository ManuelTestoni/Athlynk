import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of a hosted Stripe web flow (Checkout / Billing Portal / Connect).
enum StripeFlowResult { success, cancelled, dismissed }

/// Android counterpart of iOS `StripeWebFlow` (ASWebAuthenticationSession):
/// opens the hosted page in a Custom Tab / browser and waits for the app to
/// be re-entered via its custom scheme (`athlynk://checkout-return`, …).
///
/// Fulfillment always happens server-side via webhook — the callback host is
/// only a UX signal, exactly like iOS.
class StripeWebFlow {
  StripeWebFlow._();

  static final _appLinks = AppLinks();

  /// Opens [url]; resolves when a link with [successHost] or [cancelHost]
  /// arrives, or [timeout] passes (user closed the tab and came back some
  /// other way → dismissed).
  static Future<StripeFlowResult> run(
    String url, {
    required String scheme,
    String successHost = 'checkout-return',
    String cancelHost = 'checkout-cancel',
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final completer = Completer<StripeFlowResult>();
    late final StreamSubscription<Uri> sub;
    sub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme != scheme) return;
      if (completer.isCompleted) return;
      if (uri.host == successHost) {
        completer.complete(StripeFlowResult.success);
      } else if (uri.host == cancelHost) {
        completer.complete(StripeFlowResult.cancelled);
      } else {
        // Any other host on our scheme (e.g. subscription-return,
        // connect-return) counts as a completed round-trip.
        completer.complete(StripeFlowResult.success);
      }
    });

    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.inAppBrowserView,
    );
    if (!launched) {
      await sub.cancel();
      return StripeFlowResult.dismissed;
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return StripeFlowResult.dismissed;
    } finally {
      await sub.cancel();
    }
  }

  /// Fire-and-forget open (billing portals where no return signal matters).
  static Future<void> open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  }
}
