import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/pages/launcher/plugins/plugin_gallery.dart';
import 'package:tabame/pages/launcher/plugins/plugin_manifest.dart';
import 'package:tabame/pages/launcher/plugins/plugin_registry.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/services/extension_policy.dart';

void main() {
  group('ExtensionPolicy profile gates', () {
    test('portable keeps every plugin source and user command path available', () {
      final ExtensionPolicy policy = ExtensionPolicy.forProfile(DistributionProfile.portable);

      expect(policy.canExecutePlugins, isTrue);
      expect(policy.canFetchPluginGallery, isTrue);
      expect(policy.canInstallRemotePlugins, isTrue);
      expect(policy.canInstallPluginDependencies, isTrue);
      expect(policy.canRunUserCommandTemplates, isTrue);
      expect(policy.canRunArbitraryPowerShell, isTrue);
      for (final PluginSource source in PluginSource.values) {
        expect(policy.allowsPluginSource(source), isTrue);
      }
      expect(policy.canInstallDependenciesFor('python'), isTrue);
      expect(policy.canInstallDependenciesFor('node'), isTrue);
      expect(policy.canInstallDependenciesFor('bun'), isTrue);
    });

    for (final DistributionProfile profile in <DistributionProfile>[
      DistributionProfile.storeInstaller,
      DistributionProfile.storeMsix,
    ]) {
      test('$profile disables every executable extension source', () {
        final ExtensionPolicy policy = ExtensionPolicy.forProfile(profile);

        expect(policy.canExecutePlugins, isFalse);
        expect(policy.canFetchPluginGallery, isFalse);
        expect(policy.canInstallRemotePlugins, isFalse);
        expect(policy.canInstallPluginDependencies, isFalse);
        expect(policy.canEditLocalPluginConfiguration, isFalse);
        expect(policy.canRunUserCommandTemplates, isFalse);
        expect(policy.canRunArbitraryPowerShell, isFalse);
        expect(policy.preservePluginData, isTrue);
        for (final PluginSource source in PluginSource.values) {
          expect(policy.allowsPluginSource(source), isFalse);
        }
        expect(policy.canInstallDependenciesFor('python'), isFalse);
        expect(policy.canInstallDependenciesFor('npm'), isFalse);
        expect(policy.canInstallDependenciesFor('bun'), isFalse);
      });
    }
  });

  group('Plugin provenance classification', () {
    test('gallery entries distinguish first-party and third-party feeds', () {
      final PluginGalleryEntry firstParty = PluginGalleryEntry.fromJson(<String, dynamic>{
        'id': 'official',
        'name': 'Official',
        'runtime': 'node',
        'files': <String, String>{'plugin.json': 'https://example.test/plugin.json'},
      })!;
      final PluginGalleryEntry thirdParty = PluginGalleryEntry.fromJson(<String, dynamic>{
        'id': 'community',
        'name': 'Community',
        'source': 'thirdPartyGallery',
        'author': 'Community publisher',
        'runtime': 'python',
        'zip': 'https://example.test/community.zip',
      })!;

      expect(firstParty.source, PluginSource.firstPartyGallery);
      expect(firstParty.publisher, isEmpty);
      expect(thirdParty.source, PluginSource.thirdPartyGallery);
      expect(thirdParty.publisher, 'Community publisher');
    });

    test('missing installed provenance is local user-authored', () {
      final PluginManifest manifest = PluginManifest.fromJson(
        <String, dynamic>{
          'id': 'local',
          'name': 'Local',
          'keyword': 'local',
          'runtime': 'python',
          'entry': 'main.py',
          'enabled': true,
        },
        directory: r'C:\Users\test\Tabame\plugins\local',
        folderName: 'local',
      );

      expect(manifest.source, PluginSource.localUserAuthored);
    });
  });

  group('Store gates cannot be bypassed by configuration', () {
    test('enabled imported manifests remain blocked regardless of claimed source', () {
      final PluginManifest imported = PluginManifest.fromJson(
        <String, dynamic>{
          'id': 'imported',
          'name': 'Imported',
          'keyword': 'imported',
          'runtime': 'node',
          'entry': 'main.js',
          'enabled': true,
        },
        directory: r'C:\Users\test\Tabame\plugins\imported',
        folderName: 'imported',
        source: PluginSource.firstPartyGallery,
        publisher: 'Far-Se',
      );
      final ExtensionPolicy policy = ExtensionPolicy.forProfile(DistributionProfile.storeInstaller);

      expect(imported.enabled, isTrue);
      expect(imported.source, PluginSource.firstPartyGallery);
      expect(PluginRegistry.canExecute(imported, extensionPolicy: policy), isFalse);
      expect(
        policy.canExecutePlugin(
          id: imported.id,
          source: imported.source,
          enabled: true,
          publisher: imported.publisher,
          consentGranted: true,
          artifactHashVerified: true,
          signatureVerified: true,
        ),
        isFalse,
      );
    });

    test('downloaded code and user command targets are rejected', () {
      final ExtensionPolicy policy = ExtensionPolicy.forProfile(DistributionProfile.storeInstaller);

      expect(policy.isUnreviewedCodePath(r'C:\Downloads\plugin\main.py'), isTrue);
      expect(policy.isUnreviewedCodePath(r'C:\Downloads\plugin\main.js'), isTrue);
      expect(policy.blocksUserTarget('powershell.exe -File C:\\Downloads\\script.ps1'), isTrue);
      expect(policy.blocksUserTarget('https://nodejs.org/'), isFalse);
      expect(policy.blocksUserTarget('https://example.test/file.txt'), isFalse);
    });
  });
}
