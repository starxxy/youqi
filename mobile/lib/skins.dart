import 'package:flutter/material.dart';

/// Inject another provider into YouqiApp to add skins without changing task logic.
abstract interface class SkinProvider {
  List<String> get ids;
  SkinTokens resolve(String id, {required bool dark});
}

@immutable
class SkinTokens {
  const SkinTokens(
      {required this.background,
      required this.surface,
      required this.text,
      required this.muted,
      required this.accent,
      required this.divider,
      this.blur = 18});
  final Color background, surface, text, muted, accent, divider;
  final double blur;
}

class BuiltInSkins implements SkinProvider {
  const BuiltInSkins();
  @override
  List<String> get ids => const ['a', 'b', 'c'];
  @override
  SkinTokens resolve(String id, {required bool dark}) => SkinTokens(
      background: dark
          ? const Color(0xff20252c)
          : id == 'b'
              ? const Color(0xfff4f2fa)
              : const Color(0xfff5f7fb),
      surface: dark ? const Color(0xff2b3139) : Colors.white,
      text: dark ? const Color(0xfff4f1eb) : const Color(0xff172338),
      muted: dark ? const Color(0xffadb5c1) : const Color(0xff65748b),
      accent: id == 'c'
          ? (dark ? const Color(0xfff1be83) : const Color(0xffad7433))
          : id == 'b'
              ? (dark ? const Color(0xffc4aff4) : const Color(0xff7155bb))
              : (dark ? const Color(0xff9db6ff) : const Color(0xff315bd6)),
      divider: dark ? const Color(0xff3c444f) : const Color(0xffe2e7f0));
}
