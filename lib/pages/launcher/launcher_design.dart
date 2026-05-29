/// Defines the available visual designs for the Launcher UI.
///
/// Each variant controls the look of the search bar, results list, and all
/// result-item widgets.  The actual rendering is delegated to the per-design
/// widget factories in [LauncherDesignTheme].
enum LauncherDesign {
  /// The original design: dark glass card, accent-coloured left-bar selection
  /// indicator, compact row layout, small type-badge chips.
  classic,

  /// A calm, Serene-inspired design: frosted-glass container, SF-style
  /// typography scale, icon-well thumbnails, subtle vibrancy highlights,
  /// no coloured left bar – selection is shown through a diffuse fill.
  serene,
}
