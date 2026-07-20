import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native destination parsed out of a Chiron action link.
/// Port of iOS `CoachDeepLink`: Chiron emits relative web paths (Django
/// `reverse()` output) and the shell turns them into native navigation.
@immutable
sealed class ChironDeepLink {
  const ChironDeepLink();

  /// Parses the web paths Chiron actually emits:
  /// ```
  ///   /clienti/<id>/            → client detail
  ///   /clienti/<id>/progressi/  → client detail (progress drill-in)
  ///   /check/                   → checks dashboard
  ///   /check/<id>/              → one submitted check
  ///   /check/cliente/<id>/      → that client's checks
  /// ```
  static ChironDeepLink? parse(String rawPath) {
    // Tolerate absolute URLs as well as bare paths.
    final path = Uri.tryParse(rawPath)?.path ?? rawPath;
    final parts = path
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;

    switch (parts.first) {
      case 'clienti':
        if (parts.length >= 2) {
          final id = int.tryParse(parts[1]);
          if (id != null) return ChironClientLink(id);
        }
        return const ChironClientsLink();
      case 'check':
        if (parts.length >= 3 && parts[1] == 'cliente') {
          final id = int.tryParse(parts[2]);
          if (id != null) return ChironClientLink(id);
        }
        if (parts.length >= 2) {
          final id = int.tryParse(parts[1]);
          if (id != null) return ChironCheckLink(id);
        }
        return const ChironCheckDashboardLink();
      case 'agenda':
        return const ChironAgendaLink();
      case 'abbonamenti':
        return const ChironSubscriptionsLink();
      case 'chat':
        return const ChironMessagesLink();
      default:
        return null;
    }
  }
}

class ChironClientsLink extends ChironDeepLink {
  const ChironClientsLink();
}

class ChironClientLink extends ChironDeepLink {
  const ChironClientLink(this.clientId);
  final int clientId;
}

class ChironCheckLink extends ChironDeepLink {
  const ChironCheckLink(this.checkId);
  final int checkId;
}

class ChironCheckDashboardLink extends ChironDeepLink {
  const ChironCheckDashboardLink();
}

class ChironAgendaLink extends ChironDeepLink {
  const ChironAgendaLink();
}

class ChironSubscriptionsLink extends ChironDeepLink {
  const ChironSubscriptionsLink();
}

class ChironMessagesLink extends ChironDeepLink {
  const ChironMessagesLink();
}

/// Pending deep link — set by the Chiron chat, consumed by the coach shell.
final chironRouterProvider = StateProvider<ChironDeepLink?>((ref) => null);
