// Windows-only facade for Tabame's native plugin.
//
// The native provider remains Windows-specific. Keeping its package import in
// this adapter makes the dependency boundary explicit without changing the
// existing Windows method-channel behavior.
export 'package:tabamewin32/tabamewin32.dart';
