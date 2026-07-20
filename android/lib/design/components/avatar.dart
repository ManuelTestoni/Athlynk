import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Circular avatar — uploaded photo or bronze-filled circle with serif
/// initials (iOS `AvatarView`), soft halo.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    this.url,
    required this.name,
    this.size = 44,
  });

  final String? url;
  final String name;
  final double size;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget child;
    if (u != null && u.isNotEmpty) {
      child = ClipOval(
        child: CachedNetworkImage(
          imageUrl: u,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _fallback(),
          placeholder: (_, _) => Container(color: Palette.void2),
        ),
      );
    } else {
      child = _fallback();
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: neonGlow(Palette.amber),
      ),
      child: child,
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB8860B), Color(0xFF8A6508)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: Typo.poster(size * 0.38, color: Palette.void0),
      ),
    );
  }
}
