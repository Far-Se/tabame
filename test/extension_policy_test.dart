import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/pages/launcher/plugins/plugin_gallery.dart';
import 'package:tabame/pages/launcher/plugins/plugin_manifest.dart';
import 'package:tabame/pages/launcher/plugins/plugin_registry.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/services/extension_policy.dart';

void main() {
  group('ExtensionPolicy profile gates', () {
    for (final DistributionProfile profile in DistributionProfile.values) {
      test('$profile keeps every extension capability enabled', () {
        final ExtensionPolicy policy = ExtensionPolicy.forProfile(profile);

        expect(policy.enabled, isTrue);
        expect(policy.canExecutePlugins, isTrue);
        expect(policy.canFetchPluginGallery, isTrue);
        expect(policy.canInstallRemotePlugins, isTrue);
        expect(policy.canInstallPluginDependencies, isTrue);
        expect(policy.canEditLocalPluginConfiguration, isTrue);
        expect(policy.canRunUserCommandTemplates, isTrue);
        expect(policy.canRunArbitraryPowerShell, isTrue);
        expect(policy.preservePluginData, isTrue);
        for (final PluginSource source in PluginSource.values) {
          expect(policy.allowsPluginSource(source), isTrue);
        }
        expect(policy.canInstallDependenciesFor('python'), isTrue);
        expect(policy.canInstallDependenciesFor('npm'), isTrue);
        expect(policy.canInstallDependenciesFor('bun'), isTrue);
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

  group('Enabled policy applies to imported configuration', () {
    test('enabled imported manifests remain executable when policy is enabled', () {
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
      expect(PluginRegistry.canExecute(imported, extensionPolicy: policy), isTrue);
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
        isTrue,
      );
    });

    test('script paths remain classifiable while enabled command targets are allowed', () {
      final ExtensionPolicy policy = ExtensionPolicy.forProfile(DistributionProfile.storeInstaller);

      expect(policy.isUnreviewedCodePath(r'C:\Downloads\plugin\main.py'), isTrue);
      expect(policy.isUnreviewedCodePath(r'C:\Downloads\plugin\main.js'), isTrue);
      expect(policy.blocksUserTarget('powershell.exe -File C:\\Downloads\\script.ps1'), isFalse);
      expect(policy.blocksUserTarget('https://nodejs.org/'), isFalse);
      expect(policy.blocksUserTarget('https://example.test/file.txt'), isFalse);
    });
  });
}
