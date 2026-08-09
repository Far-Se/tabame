import 'dart:io';

/// Resolved locations supplied by the host application-data provider.
///
/// For a packaged Windows process these correspond to
/// `Windows.Storage.ApplicationData.Current.LocalFolder`,
/// `LocalCacheFolder`, and `TemporaryFolder`.
class AppDataLocations {
  const AppDataLocations({
    required this.localFolder,
    required this.localCacheFolder,
    required this.temporaryFolder,
  });

  final Directory localFolder;
  final Directory localCacheFolder;
  final Directory temporaryFolder;
}
