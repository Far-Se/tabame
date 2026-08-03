// ignore_for_file: dead_code, curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _Logger {
  static const bool logging = false; // set to false for release
  static const bool hookLogging = false; // set to false for release
  static void log(String message) {
    debugPrint(message);
  }
}

/// The [CustomMouseCursor] class allows the user to create custom system mouse
/// cursors from various sources on **Windows**.
///
/// See [MouseCursor] for more information on using cursors within flutter.
/// [CustomMouseCursor] cursor objects can be used just as you would any
/// [SystemMouseCursor] built in cursor from [SystemMouseCursors].
///
/// ## Using cursors
///
/// A [CustomMouseCursor] object is used by being assigned to a [MouseRegion] or
/// another widget that exposes the [MouseRegion] API, such as
/// [InkResponse.mouseCursor].  This is behavior is identical for any
/// [MouseCursor] subclass.
///
/// The [asset] and [exactAsset] static methods can be use to create custom
/// cursors from flutter assets.
///
/// The [icon] static method can be used to create custom cursors from any
/// flutter [IconData].
///
/// The [image] static method can be used to create icon's from [ui.Image]
/// objects.  The image will be scaled to create cursors for any other
/// encountered devicePixelRatio.  The image is supplied with its native
/// devicePixelRatio.  The image should have a devicePixelRatio large enough
/// that it is scaled down for most encountered devicePixelRatios. (at least 2.0
/// typically).
///
//ignore: must_be_immutable
class CustomMouseCursor extends MouseCursor {
  /// This is the cursor's key — the name registered with the Windows platform
  /// cursor system.  It is final.
  final String _key;

  String get key => _key;

  /// The origin story for this cursor, whether it was created from an exact
  /// asset, a DPI aware AssetImage, an icon or an image.  This is used to
  /// decide how to RE-create the cursor when the DPI/DevicePixelRatio changes.
  // ignore: library_private_types_in_public_api
  final _CustomMouseCursorCreationType originStory;

  /// When the DevicePixelRatio is different or changes from this size the
  /// pointer will be scaled accordingly when
  /// CustomMousePointer.didChangeDependencies() is called.
  /// The user should always call CustomMousePointer.didChangeDependencies()
  /// from their top level widget's didChangeDependencies() handler to ensure
  /// that pointers change to DPI/DevicePixelRatio dependent sizes.
  final double nativeDevicePixelRatio;

  /// This is the X location of hot spot at the [nativeDevicePixelRatio]
  /// This gets scaled accordingly on DPI changes.
  final int hotXAtNativeDevicePixelRatio;

  /// This is the Y location of hot spot at the [nativeDevicePixelRatio]
  /// This gets scaled accordingly on DPI changes.
  final int hotYAtNativeDevicePixelRatio;

  /// The DevicePixelRatio for which the current backing cursor was created.
  double currentCursorDevicePixelRatio;

  /// If [originStory]==[_CustomMouseCursorCreationType.asset] then this
  /// contains the [AssetImage] used in its creation (and used for updating on
  /// DevicePixelRatio changes).
  /// If [originStory]==[_CustomMouseCursorCreationType.exactasset] then this
  /// contains the [ExactAssetImage] used in its creation (and used for updating
  /// on DevicePixelRatio changes).
  AssetBundleImageProvider? _assetBundleImageProvider;

  /// This was exactAssetDevicePixelRatio passed to exactasset() - otherwise it
  /// will match nativeDevicePixelRatio.
  double? _exactAssetDevicePixelRatio;

  _CustomMouseCursorFromIconOriginInfo? _iconCreationInfo;

  /// This holds cache of the bitmaps/info we have made for this bitmap for
  /// different DevicePixelRatio monitors.
  final Map<double, _CustomMouseCursorDPRBitmapCache> _dprBitmapCache = <double, _CustomMouseCursorDPRBitmapCache>{};

  /// Cache of all the created custom cursors
  static final Map<String, CustomMouseCursor> _cursorCacheOfAllCreatedCursors = <String, CustomMouseCursor>{};

  CustomMouseCursor._(
    this._key,
    this.originStory,
    this.nativeDevicePixelRatio,
    this.hotXAtNativeDevicePixelRatio,
    this.hotYAtNativeDevicePixelRatio,
    this.currentCursorDevicePixelRatio,
  ) : assert(_key != "");

  /// Creates a cursor with the image obtained from an exact asset bundle. The
  /// key for the image is given by the [assetName] argument.  Using this method
  /// allows the pixel-density-aware asset resolution to be avoided.
  ///
  /// This method works the same as [asset] but allows the user to specify the
  /// *exact* image resource that they would like to load.  This bypasses the
  /// consideration of devicePixelRatio when loading the image and instead
  /// loads the exact asset resource specified by the [assetName].  (Internally
  /// this is implemented with a call to [asset] with the [useExactAssetImage]
  /// argument set to true).
  ///
  /// The [package] argument must be non-null when displaying an image from a
  /// package and null otherwise.
  ///
  /// If the [bundle] argument is omitted or null, then the [DefaultAssetBundle]
  /// will be used.
  static Future<CustomMouseCursor> exactAsset(
    String assetName, {
    int hotX = 0,
    int hotY = 0,
    double nativeDevicePixelRatio = 1.0,
    CustomMouseCursor? existingCursorToUpdate,
    BuildContext? context,
    AssetBundle? bundle,
    String? package,
  }) async {
    return asset(
      assetName,
      hotX: hotX,
      hotY: hotY,
      nativeDevicePixelRatio: nativeDevicePixelRatio,
      existingCursorToUpdate: existingCursorToUpdate,
      context: context,
      bundle: bundle,
      useExactAssetImage: true,
      package: package,
    );
  }

  /// Creates a cursor with the image obtained from an asset bundle.  The key
  /// for the image is given by the [assetName] argument.
  ///
  /// By default, the pixel-density-aware asset resolution will be attempted.
  ///
  /// See also:
  ///  * [AssetImage], which is used to implement the behavior when the scale
  ///    is omitted.
  ///  * [ExactAssetImage], which is used to implement the behavior when the
  ///    scale is present.
  ///  * <https://flutter.dev/assets-and-images/>, an introduction to assets in
  ///    Flutter.
  static Future<CustomMouseCursor> asset(
    String assetName, {
    int hotX = 0,
    int hotY = 0,
    double nativeDevicePixelRatio = 1.0,
    CustomMouseCursor? existingCursorToUpdate,
    BuildContext? context,
    bool useExactAssetImage = false,
    AssetBundle? bundle,
    String? package,
  }) async {
    double exactAssetDevicePixelRatio = nativeDevicePixelRatio;
    if (_Logger.logging) {
      _Logger.log(
          ('\n\n${useExactAssetImage ? 'EXACT' : ''}Asset() assetName=$assetName useExactAssetImage=$useExactAssetImage nativeDevicePixelRatio=$nativeDevicePixelRatio existingCursorToUpdate=$existingCursorToUpdate'));
    }

    AssetBundleImageProvider? assetBundleImageProvider;
    AssetBundleImageKey? assetAwareKey;
    double rescaleRatioRequiredForImage = 0;

    _lastImageConfiguration ??= _createLocalImageConfigurationWithOrWithoutContext(context: context);

    if (_lastImageConfiguration == null || _lastImageConfiguration!.devicePixelRatio == null) {
      // THIS CASE SHOULD NEVER BE ABLE TO HAPPEN on Windows
      throw ('Unknown DevicePixelRatio in asset');
    }

    assetBundleImageProvider = useExactAssetImage
        ? ExactAssetImage(assetName, bundle: bundle, package: package)
        : AssetImage(assetName, bundle: bundle, package: package);
    assetAwareKey = await assetBundleImageProvider.obtainKey(_lastImageConfiguration!);
    if (_Logger.logging) {
      _Logger.log('  _lastImageConfiguration returned DPR of ${_lastImageConfiguration!.devicePixelRatio} for system');
      _Logger.log('  assetAwareKey was obtainKey`ed() to be ${assetAwareKey.name} scale=${assetAwareKey.scale}');
    }

    if (nativeDevicePixelRatio != 1.0 && assetAwareKey.scale == 1.0) {
      // WE were told that the 1.0 is actually [nativeDevicePixelRatio] SO USE
      // THAT (ExactImageAsset() will always return scale of 1.0)
      rescaleRatioRequiredForImage = _lastImageConfiguration!.devicePixelRatio! / nativeDevicePixelRatio;
      if (_Logger.logging) {
        _Logger.log(
            '  ASSETAWAREKEY SCALE==1.0 SPECIAL CASE  nativeDevicePixelRatio=$nativeDevicePixelRatio  exactAssetDevicePixelRatio=$exactAssetDevicePixelRatio');
        _Logger.log('  made  rescaleRatioRequiredForImage=$rescaleRatioRequiredForImage');
      }
    } else {
      rescaleRatioRequiredForImage = _lastImageConfiguration!.devicePixelRatio! / assetAwareKey.scale;
    }

    if (_Logger.logging) {
      _Logger.log(
          '  Using lastImageConfiguration got rescaleRatioRequiredForImage=$rescaleRatioRequiredForImage  name=${assetAwareKey.name} scale=${assetAwareKey.scale}');
    }

    if (nativeDevicePixelRatio != _lastImageConfiguration!.devicePixelRatio!) {
      if (_Logger.logging) {
        _Logger.log('  CHANGING NATIVE PIXEL RATIO (OLD DPR=$nativeDevicePixelRatio hotX=$hotX hotY=$hotY)');
      }
      double adjustHotsToNativeDPRChange = _lastImageConfiguration!.devicePixelRatio! / nativeDevicePixelRatio;
      hotX = (hotX * adjustHotsToNativeDPRChange).round();
      hotY = (hotY * adjustHotsToNativeDPRChange).round();
      nativeDevicePixelRatio = _lastImageConfiguration!.devicePixelRatio!;
      if (!useExactAssetImage) {
        exactAssetDevicePixelRatio = nativeDevicePixelRatio;
      }
      if (_Logger.logging) {
        _Logger.log(
            '  UPDATED values DPR nativeDevicePixelRatio=$nativeDevicePixelRatio hotX=$hotX hotY=$hotY   exactAssetDevicePixelRatio=$exactAssetDevicePixelRatio');
      }
    }

    assetName = assetAwareKey.name;

    // Check the cache for an existing cursor with this assetname
    if (_cursorCacheOfAllCreatedCursors.containsKey(assetName)) {
      if (_Logger.logging) {
        _Logger.log('  Found cursor in cache with assetname =$assetName');
      }
      return _cursorCacheOfAllCreatedCursors[assetName]!;
    }

    final ByteData rawAssetImageBytes = await rootBundle.load(assetName);
    final Uint8List rawUint8 = rawAssetImageBytes.buffer.asUint8List();

    final ui.Image uiImage = await _createUIImageFromPNGUint8ListBufferAndPossiblyScale(
      rawUint8,
      rescaleRatioRequiredForImage: rescaleRatioRequiredForImage,
    );

    if (_Logger.logging) {
      _Logger.log('  Loaded Asset image width=${uiImage.width} height=${uiImage.height}');
    }

    final CustomMouseCursor cursor = await _commonCursorImageInstaller(
      uiImage,
      hotX,
      hotY,
      nativeDevicePixelRatio,
      key: assetName,
      originStory:
          useExactAssetImage ? _CustomMouseCursorCreationType.exactasset : _CustomMouseCursorCreationType.asset,
      existingCursorToUpdate: existingCursorToUpdate,
    );

    cursor._assetBundleImageProvider = assetBundleImageProvider;
    cursor._exactAssetDevicePixelRatio = exactAssetDevicePixelRatio;

    return cursor;
  }

  /// This is similar to asset() but for UPDATING a cursor with an additional
  /// devicePixelRatio version.  If the cursor was created with asset() then
  /// AssetImage() is used to get the closest image to the requested
  /// [newDevicePixelRatio], otherwise ExactAssetImage() is used and the same
  /// asset used originally is used again.
  Future<void> _updateAssetToNewDpi(double newDevicePixelRatio) async {
    assert(
      originStory == _CustomMouseCursorCreationType.asset || originStory == _CustomMouseCursorCreationType.exactasset,
      '_updateAssetToNewDpi() called on non asset cursor ($originStory key=$key)',
    );
    assert(_assetBundleImageProvider != null);

    if (_Logger.logging) {
      _Logger.log(
          ('ENTERING _updateAssetToNewDpi( newDevicePixelRatio=$newDevicePixelRatio )   nativeDevicePixelRatio=$nativeDevicePixelRatio _exactAssetDevicePixelRatio=$_exactAssetDevicePixelRatio'));
    }
    final bool useExactAssetImage = (originStory == _CustomMouseCursorCreationType.exactasset);

    late final double rescaleRatioRequiredForImage;
    final ImageConfiguration forcedImageConfig =
        _createLocalImageConfigurationWithOrWithoutContext(forceDevicePixelRatio: newDevicePixelRatio);

    final AssetBundleImageKey assetAwareKey = await _assetBundleImageProvider!.obtainKey(forcedImageConfig);

    if (_Logger.logging) {
      _Logger.log('  forcedImageConfig returned DPR of ${forcedImageConfig.devicePixelRatio} for system');
      _Logger.log('  assetAwareKey was obtainKey`ed() to be ${assetAwareKey.name} scale=${assetAwareKey.scale}');
    }

    if (useExactAssetImage && _exactAssetDevicePixelRatio != 1.0 && assetAwareKey.scale == 1.0) {
      rescaleRatioRequiredForImage = newDevicePixelRatio / _exactAssetDevicePixelRatio!;
      if (_Logger.logging) {
        _Logger.log(
            '  ASSETAWAREKEY SCALE==1.0 SPECIAL CASE  _exactAssetDevicePixelRatio=$_exactAssetDevicePixelRatio');
        _Logger.log('  made  rescaleRatioRequiredForImage=$rescaleRatioRequiredForImage');
      }
    } else {
      rescaleRatioRequiredForImage = newDevicePixelRatio / assetAwareKey.scale;
    }

    // HOT SPOTS were originally STORED at [nativeDevicePixelRatio] DPR, so we
    // must adjust them to [newDevicePixelRatio].
    double adjustHotSpotRatio = newDevicePixelRatio / nativeDevicePixelRatio;
    double hotX = hotXAtNativeDevicePixelRatio * adjustHotSpotRatio;
    double hotY = hotYAtNativeDevicePixelRatio * adjustHotSpotRatio;

    if (_Logger.logging) {
      _Logger.log(
          '  _updateAssetToNewDpi() updating by LOADING asset ${assetAwareKey.name} scale=${assetAwareKey.scale} rescaleRatioRequiredForImage=$rescaleRatioRequiredForImage adjusted adjustHotSpotRatio=$adjustHotSpotRatio hotX=$hotX hotY=$hotY');
    }
    final ByteData rawAssetImageBytes = await rootBundle.load(assetAwareKey.name);
    final Uint8List rawUint8 = rawAssetImageBytes.buffer.asUint8List();

    final ui.Image uiImage = await _createUIImageFromPNGUint8ListBufferAndPossiblyScale(
      rawUint8,
      rescaleRatioRequiredForImage: rescaleRatioRequiredForImage,
    );

    if (_Logger.logging) {
      _Logger.log('  _updateAssetToNewDpi() UPDATE Asset loaded image width=${uiImage.width} height=${uiImage.height}');
      _Logger.log(
          '  calling _commonCursorImageInstaller() with EXISTING ASSET CURSOR newDevicePixelRatio=$newDevicePixelRatio');
    }
    await _commonCursorImageInstaller(
      uiImage,
      hotX.round(),
      hotY.round(),
      newDevicePixelRatio,
      key: key,
      originStory: originStory,
      existingCursorToUpdate: this,
    );
  }

  /// Creates a custom mouse cursor with a glyph from a font described in an
  /// [IconData] such as material's predefined [IconData]s in [Icons].
  ///
  /// The size (in logical pixels) of the icon used for the cursor is specified
  /// with the [size] argument.  The hot spot location (in logical pixels) is
  /// specified with the [hotX] and [hotY] arguments.
  static Future<CustomMouseCursor> icon(
    final IconData icon, {
    double size = 32,
    int hotX = 0,
    int hotY = 0,
    final double? fill,
    final double? weight,
    final double? grade,
    final double? opticalSize,
    final Color color = Colors.black,
    final List<Shadow>? shadows,
    CustomMouseCursor? existingCursorToUpdate,
  }) async {
    assert(fill == null || (0.0 <= fill && fill <= 1.0));
    assert(weight == null || (0.0 < weight));
    assert(opticalSize == null || (0.0 < opticalSize));

    final _CustomMouseCursorFromIconOriginInfo iconCreationInfo = _CustomMouseCursorFromIconOriginInfo(
      icon: icon,
      sizeInLogicalPixels: size,
      hotXInLogicalPixels: hotX,
      hotYInLogicalPixels: hotY,
      fill: fill,
      weight: weight,
      opticalSize: opticalSize,
      grade: grade,
      color: color,
      shadows: shadows,
    );

    double currentDevicePixelRatio = _getCurrentDevicePixelRatioFromLastConfigOrWindow();
    if (currentDevicePixelRatio != 1.0) {
      if (_Logger.logging) {
        _Logger.log(('\nEntering ICON creation currentDevicePixelRatio=$currentDevicePixelRatio'));
        _Logger.log('  Must adjust size=$size   hotX=$hotX   hotY=$hotY ');
      }
      double adjustRatio = currentDevicePixelRatio / 1.0;
      size = size * adjustRatio;
      hotX = (hotX * adjustRatio).round();
      hotY = (hotY * adjustRatio).round();
      if (_Logger.logging) {
        _Logger.log('  ADJUSTED adjust size=$size   hotX=$hotX   hotY=$hotY ');
      }
    }

    final ui.Image iconImage = _createImageFromIconSync(
      icon,
      size: size,
      color: color,
      iconFill: fill,
      iconWeight: weight,
      iconGrade: grade,
      iconOpticalSize: opticalSize,
      shadows: shadows,
    );

    final CustomMouseCursor cursor = await _commonCursorImageInstaller(
      iconImage,
      hotX,
      hotY,
      currentDevicePixelRatio,
      originStory: _CustomMouseCursorCreationType.icon,
      existingCursorToUpdate: existingCursorToUpdate,
    );

    cursor._iconCreationInfo = iconCreationInfo;

    return cursor;
  }

  /// Internal handler for updating custom icon cursors in response to changes
  /// to the system's devicePixelRatio.
  Future<void> _updateIconToNewDpi(double newDevicePixelRatio) async {
    assert(originStory == _CustomMouseCursorCreationType.icon, '_updateIconToNewDpi() called on non icon cursor');

    if (_iconCreationInfo == null) return;

    final double scaleRatio = newDevicePixelRatio;
    final double newSize = _iconCreationInfo!.sizeInLogicalPixels * scaleRatio;
    final int newHotX = (_iconCreationInfo!.hotXInLogicalPixels * scaleRatio).round();
    final int newHotY = (_iconCreationInfo!.hotYInLogicalPixels * scaleRatio).round();

    if (_Logger.logging) {
      _Logger.log(('  updateIconToNewDpi() making icon at newSize=$newSize   (scaleRatio=$scaleRatio)'));
    }
    final ui.Image iconImage = _createImageFromIconSync(
      _iconCreationInfo!.icon,
      size: newSize,
      color: _iconCreationInfo!.color,
      iconFill: _iconCreationInfo!.fill,
      iconWeight: _iconCreationInfo!.weight,
      iconGrade: _iconCreationInfo!.grade,
      iconOpticalSize: _iconCreationInfo!.opticalSize,
      shadows: _iconCreationInfo!.shadows,
    );
    if (_Logger.logging) {
      _Logger.log(
          '  CALLING _commonCursorImageInstaller() with EXISTING ICON IMAGE TO UPDATE WITH NEW icon Image newDevicePixelRatio=$newDevicePixelRatio');
    }
    // FIX: previously this Future was NOT awaited.
    await _commonCursorImageInstaller(
      iconImage,
      newHotX,
      newHotY,
      newDevicePixelRatio,
      originStory: _CustomMouseCursorCreationType.icon,
      existingCursorToUpdate: this,
    );
  }

  /// Creates a [CustomMouseCursor] from the supplied ui.Image buffer.
  /// The image is supplied with its native devicePixelRatio.  The image should
  /// have a devicePixelRatio large enough that it is scaled down for most
  /// encountered devicePixelRatios (at least 2.0 typically).
  /// The [addImage] method can be used to supply additional images for
  /// specific devicePixelRatios.  These additional images are used only at
  /// their specific DPR.  The original image passed to [image] initially is
  /// always the one chosen for scaling for other encountered DPRs which do not
  /// exactly match the DPRs of any images added using [addImage].
  /// If [addImage] will be being called then pass
  /// [finalizeForCurrentDPR]=false to prevent the cursor from having a image
  /// made for the current DPR.
  static Future<CustomMouseCursor> image(
    ui.Image uiImage, {
    int hotX = 0,
    int hotY = 0,
    double thisImagesDevicePixelRatio = 1.0,
    bool finalizeForCurrentDPR = true,
    String? key,
  }) async {
    if (_Logger.logging) {
      _Logger.log(('image() - creating custom cursor from ${thisImagesDevicePixelRatio}x image'));
    }
    final CustomMouseCursor cursor = await _commonCursorImageInstaller(
      uiImage,
      hotX,
      hotY,
      thisImagesDevicePixelRatio,
      key: key,
    );

    if (finalizeForCurrentDPR) {
      await cursor.finalizeImages();
    }
    return cursor;
  }

  /// Adds an additional image (at additional DPR) to the custom cursor.  This
  /// allows supplying additional images at other DevicePixelRatios.
  /// This can also replace existing dpr images previously set for this cursor.
  Future<void> addImage(
    ui.Image uiImage, {
    double thisImagesDevicePixelRatio = 1.0,
  }) async {
    if (originStory != _CustomMouseCursorCreationType.image) {
      throw ('addImage() called on CustomMouseCursor that was not created via image() ($originStory)');
    }
    if (_Logger.logging) {
      _Logger.log(('addImage() - adding ${thisImagesDevicePixelRatio}x image to custom cursor'));
    }
    final double rescaleRatioRequiredForImage = thisImagesDevicePixelRatio / nativeDevicePixelRatio;
    final int hotX = (hotXAtNativeDevicePixelRatio * rescaleRatioRequiredForImage).round();
    final int hotY = (hotYAtNativeDevicePixelRatio * rescaleRatioRequiredForImage).round();

    final int width = uiImage.width;
    final int height = uiImage.height;

    // Windows uses raw BGRA pixel buffers.
    final Uint8List imageBuffer = await _getBytesAsBGRAFromImage(uiImage);

    _dprBitmapCache[thisImagesDevicePixelRatio] =
        _CustomMouseCursorDPRBitmapCache(imageBuffer, width, height, hotX, hotY);

    if (_Logger.logging) {
      _Logger.log(
          '  addImage() SCALED hotspot by dpr/$nativeDevicePixelRatio => adjustHotSpotRatio=$rescaleRatioRequiredForImage  (changed to hotX=$hotX hotY=$hotY)');
    }
  }

  /// Finalizes images for the current DevicePixelRatio if needed.
  Future<void> finalizeImages() async {
    if (originStory != _CustomMouseCursorCreationType.image) {
      throw ('finalizeImages() called on CustomMouseCursor that was not created via image() ($originStory)');
    }
    double currentDevicePixelRatio = _getCurrentDevicePixelRatioFromLastConfigOrWindow();
    if (currentCursorDevicePixelRatio != currentDevicePixelRatio) {
      if (_Logger.logging) {
        _Logger.log('  finalizeImages() Creating image icon version for current DPR of $currentDevicePixelRatio');
      }
      await _updateImageToNewDpi(currentDevicePixelRatio);
    }
  }

  /// Internal handler for updating custom image cursors in response to changes
  /// to the system's devicePixelRatio.
  Future<void> _updateImageToNewDpi(double newDevicePixelRatio) async {
    assert(originStory == _CustomMouseCursorCreationType.image,
        '_updateImageToNewDpi() called on non image cursor ($originStory key=$key)');

    if (_Logger.logging) {
      _Logger.log(('ENTERING _updateImageToNewDpi( newDevicePixelRatio=$newDevicePixelRatio ) '));
    }

    if (!_dprBitmapCache.containsKey(nativeDevicePixelRatio)) {
      throw ('_updateImageToNewDpi() could not find dpr entry of $nativeDevicePixelRatio to retrieve original bitmap');
    }

    // Check to see if we have THIS DPR available in the cache and switch if
    // possible.
    if (switchToCachedDevicePixelRatioIfPossible(newDevicePixelRatio)) {
      return;
    }

    // Otherwise we need to create a new bitmap for this DPR by scaling the
    // native one.
    final double rescaleRatioRequiredForImage = newDevicePixelRatio / nativeDevicePixelRatio;
    final double hotX = hotXAtNativeDevicePixelRatio * rescaleRatioRequiredForImage;
    final double hotY = hotYAtNativeDevicePixelRatio * rescaleRatioRequiredForImage;

    if (_Logger.logging) {
      _Logger.log('  nativeDevicePixelRatio=$nativeDevicePixelRatio  cache has _dprBitmapCache=$_dprBitmapCache');
      _Logger.log(
          '  _updateImageToNewDpi() updating by SCALING image/hotspot by adjustHotSpotRatio=$rescaleRatioRequiredForImage  (changed to hotX=$hotX hotY=$hotY)');
    }

    // On windows our buffer is in raw BGRA format — decode it back to a
    // ui.Image so it can be re-scaled.
    final _CustomMouseCursorDPRBitmapCache cacheEntry = _dprBitmapCache[nativeDevicePixelRatio]!;
    final Uint8List rawBgraUint8 = cacheEntry.imageBuffer;

    if (_Logger.logging) {
      _Logger.log(('about to use decodeImageFromPixels() to decode BGRA buffer and scale'));
    }
    final Completer<ui.Image> completer = Completer<ui.Image>();
    decodeImageFromPixels(
      rawBgraUint8,
      cacheEntry.width,
      cacheEntry.height,
      PixelFormat.bgra8888,
      completer.complete,
      targetWidth: (cacheEntry.width * rescaleRatioRequiredForImage).round(),
      targetHeight: (cacheEntry.height * rescaleRatioRequiredForImage).round(),
      allowUpscaling: true,
    );
    final ui.Image uiImage = await completer.future;
    if (_Logger.logging) {
      _Logger.log(('DONE WITH decodeImageFromPixels() width=${uiImage.width} height=${uiImage.height}'));
      _Logger.log(
          '  calling _commonCursorImageInstaller() with EXISTING IMAGE CURSOR newDevicePixelRatio=$newDevicePixelRatio');
    }
    await _commonCursorImageInstaller(
      uiImage,
      hotX.round(),
      hotY.round(),
      newDevicePixelRatio,
      key: key,
      originStory: _CustomMouseCursorCreationType.image,
      existingCursorToUpdate: this,
    );
  }

  /// _commonCursorImageInstaller() creates cursor from ui.Image.  This is
  /// primarily an internal method for the asset(), exactasset() and icon()
  /// methods.  It is left exposed to allow for flexibility of user's creating
  /// cursors from any ui.Image.
  static Future<CustomMouseCursor> _commonCursorImageInstaller(
    ui.Image uiImage,
    int hotX,
    int hotY,
    double thisImagesDevicePixelRatio, {
    String? key,
    _CustomMouseCursorCreationType originStory = _CustomMouseCursorCreationType.image,
    CustomMouseCursor? existingCursorToUpdate,
  }) async {
    if (_Logger.logging) {
      _Logger.log(('ENTERING _commonCursorImageInstaller() with existingCursorToUpdate=$existingCursorToUpdate'));
    }
    // Ensure we have callbacks to detect DevicePixelRatio changes.
    _setupViewsOnMetricChangedCallbacks();

    final int width = uiImage.width;
    final int height = uiImage.height;

    late double currentDevicePixelRatio;
    if (_lastImageConfiguration != null) {
      if (_Logger.logging) {
        _Logger.log(
            '  Using lastImageConfiguration devicePixelRatio = ${_lastImageConfiguration?.devicePixelRatio ?? 'ImageConfiguration MISSING DEVICEPIXELRATIO'}');
      }
      currentDevicePixelRatio = _getCurrentDevicePixelRatioFromLastConfigOrWindow();
    } else {
      currentDevicePixelRatio = _getCurrentDevicePixelRatioFromWindow();
      if (_Logger.logging) {
        _Logger.log(
            '  _commonCursorImageInstaller() existingCursorToUpdate=$existingCursorToUpdate  Current currentDevicePixelRatio from WidgetsBinding! devicePixelRatio = $currentDevicePixelRatio');
      }
    }

    // If a different DPR was sent for the image that does NOT match the
    // [currentDevicePixelRatio] then the passed [thisImagesDevicePixelRatio]
    // will be used.  (We assume caller knows what they want)
    if (currentDevicePixelRatio != thisImagesDevicePixelRatio) {
      if (_Logger.logging) {
        _Logger.log(
            '  !!!!!! In _commonCursorImageInstaller() Creation and thisImagesDevicePixelRatio DPR ($currentDevicePixelRatio) != NATIVE ($thisImagesDevicePixelRatio)');
      }
      currentDevicePixelRatio = thisImagesDevicePixelRatio;
      if (_Logger.logging) {
        _Logger.log(
            '  CHANGED CURRENT TO MATCH thisImagesDevicePixelRatio=$thisImagesDevicePixelRatio FOR THIS CREATION');
      }
    }

    // Windows: convert ui.Image to raw BGRA pixels.
    final Uint8List imageBuffer = await _getBytesAsBGRAFromImage(uiImage);

    if (existingCursorToUpdate == null) {
      // CREATING A NEW CURSOR
      if (_Logger.logging) {
        _Logger.log('  in _commonCursorImageInstaller() CREATING NEW CURSOR');
      }
      key ??= generateUniqueKey();

      final String registeredKey = await _CustomMouseCursorPlatformInterface.registerCursor(
        key,
        imageBuffer,
        width,
        height,
        hotX.toDouble(),
        hotY.toDouble(),
      );
      assert(registeredKey == key);

      final CustomMouseCursor cursor = CustomMouseCursor._(
        registeredKey,
        originStory,
        thisImagesDevicePixelRatio,
        hotX,
        hotY,
        currentDevicePixelRatio,
      );

      cursor._dprBitmapCache[thisImagesDevicePixelRatio] =
          _CustomMouseCursorDPRBitmapCache(imageBuffer, width, height, hotX, hotY);

      _cursorCacheOfAllCreatedCursors[key] = cursor;
      return cursor;
    } else {
      // UPDATING an existing cursor's backing image with a new DPR version.
      key = existingCursorToUpdate.key;
      if (_Logger.logging) {
        _Logger.log('  WE ARE in _commonCursorImageInstaller() UPDATING the backing image key=$key');
      }
      // Delete previous version, then create new version with new dpi image.
      _CustomMouseCursorPlatformInterface.deleteCursor(key);
      final String newRegisteredKey = await _CustomMouseCursorPlatformInterface.registerCursor(
        key,
        imageBuffer,
        width,
        height,
        hotX.toDouble(),
        hotY.toDouble(),
      );
      assert(newRegisteredKey == key);

      existingCursorToUpdate._dprBitmapCache[thisImagesDevicePixelRatio] =
          _CustomMouseCursorDPRBitmapCache(imageBuffer, width, height, hotX, hotY);

      existingCursorToUpdate.currentCursorDevicePixelRatio = thisImagesDevicePixelRatio;
      return existingCursorToUpdate;
    }
  }

  // Calls the appropriate updateXXXXToNewDpi() method depending on this
  // cursor's type ([originStory]).
  Future<void> _updateCursorToNewDpr(double newDevicePixelRatio) async {
    if (_Logger.logging) {
      _Logger.log('    UPDATING $originStory CURSOR dpr - CALLING cursor.updateXXXXToNewDpi( $newDevicePixelRatio );');
    }
    if (originStory == _CustomMouseCursorCreationType.asset ||
        originStory == _CustomMouseCursorCreationType.exactasset) {
      await _updateAssetToNewDpi(newDevicePixelRatio);
    } else if (originStory == _CustomMouseCursorCreationType.icon) {
      await _updateIconToNewDpi(newDevicePixelRatio);
    } else if (originStory == _CustomMouseCursorCreationType.image) {
      await _updateImageToNewDpi(newDevicePixelRatio);
    }
  }

  /// Switch this cursor to a different DPR if it is found in the cache.
  /// Returns true if [desiredDevicePixelRatio] is in the cache and the switch
  /// is made.  false if [desiredDevicePixelRatio] is not found in the cache.
  bool switchToCachedDevicePixelRatioIfPossible(double desiredDevicePixelRatio) {
    if (_dprBitmapCache.containsKey(desiredDevicePixelRatio)) {
      if (_Logger.logging) {
        _Logger.log('    Getting DPR $desiredDevicePixelRatio from cursors BITMAP cache!!!');
      }
      final _CustomMouseCursorDPRBitmapCache cachedInfo = _dprBitmapCache[desiredDevicePixelRatio]!;
      // WE ARE UPDATING an existing cursor's backing image, so delete previous
      // image and register new one with cached bitmap.
      _CustomMouseCursorPlatformInterface.deleteCursor(key);
      // FIX: previously this Future was NOT awaited; however this method is
      // synchronous.  We use .then(...) to ensure the call is dispatched while
      // keeping the API synchronous (callers expect a sync bool result).  Any
      // subsequent setSystemCursor() will still occur after Windows has
      // processed the createCustomCursor message because both go through the
      // same platform channel in order.
      _CustomMouseCursorPlatformInterface.registerCursor(
        key,
        cachedInfo.imageBuffer,
        cachedInfo.width,
        cachedInfo.height,
        cachedInfo.hotX.toDouble(),
        cachedInfo.hotY.toDouble(),
      );
      currentCursorDevicePixelRatio = desiredDevicePixelRatio;
      return true;
    }
    return false;
  }

  @override
  MouseCursorSession createSession(int device) => _CustomMouseCursorSession(this, device);

  @override
  String get debugDescription => objectRuntimeType(this, 'CustomMouseCursor');

  /// Returns true if this cursor object is still valid and its platform
  /// backing cursor has not been deleted.
  bool get isValid => _cursorCacheOfAllCreatedCursors.containsKey(key);

  /// Frees the platform cursor and removes this cursor from the
  /// [_cursorCacheOfAllCreatedCursors].
  void dispose() {
    _CustomMouseCursorPlatformInterface.deleteCursor(key);
    _cursorCacheOfAllCreatedCursors.remove(key);
  }

  /// Disposes of all created cursors.
  static void disposeAll() {
    if (_Logger.logging) {
      _Logger.log('disposeAll() called');
    }
    // Take a snapshot before iterating — dispose() calls remove() on the same
    // map, so iterating .values directly throws ConcurrentModificationError.
    final List<CustomMouseCursor> all = _cursorCacheOfAllCreatedCursors.values.toList();
    _cursorCacheOfAllCreatedCursors.clear();
    for (final CustomMouseCursor cursor in all) {
      if (_Logger.logging) {
        _Logger.log('Calling dispose on ${cursor.key}');
      }
      _CustomMouseCursorPlatformInterface.deleteCursor(cursor.key);
    }
  }

  static ImageConfiguration? _lastImageConfiguration;
  static double _lastEnsuredDevicePixelRatio = 0;

  /// This method ensures that all pointers have support for any changes to the
  /// devicePixelRatio.  This can happen on windows moving to new monitors with
  /// different DPR or by changing system settings for display.  This is called
  /// from our onMetricsChanged() hook or by user themselves (typically from
  /// their root widget's didChangeDependencies() handler).
  static Future<void> ensurePointersMatchDevicePixelRatio(BuildContext? context) async {
    if (_Logger.logging) {
      _Logger.log(('ENTERED ensurePointersMatchDevicePixelRatio()'));
    }
    double devicePixelRatio = _getDevicePixelRatioFromView();
    if (devicePixelRatio == _lastEnsuredDevicePixelRatio) {
      if (_Logger.logging) {
        _Logger.log(('  lastEnsuredDevicePixelRatio IMMEDIATE RETURN already $_lastEnsuredDevicePixelRatio'));
      }
      return;
    }

    _lastImageConfiguration = _createLocalImageConfigurationWithOrWithoutContext(context: context);

    double currentDevicePixelRatio = _lastImageConfiguration?.devicePixelRatio ?? devicePixelRatio;

    if (_Logger.logging) {
      _Logger.log('  Determined Current currentDevicePixelRatio= $currentDevicePixelRatio');
      _Logger.log(
          '  createLocalImageConfiguration  devicePixelRatio=${_lastImageConfiguration!.devicePixelRatio}  platform=${_lastImageConfiguration!.platform}');
      _Logger.log('\n\n  CHECKING ALL CURSORS==============================================');
    }
    for (final CustomMouseCursor cursor in _cursorCacheOfAllCreatedCursors.values) {
      if (_Logger.logging) {
        _Logger.log(
            '\n--------------------------------------------------------\n    Checking DPR for cursor.originStory=${cursor.originStory}  key=${cursor.key}  ');
      }
      if (cursor.currentCursorDevicePixelRatio != currentDevicePixelRatio) {
        if (_Logger.logging) {
          _Logger.log(
              '    Current DPI is different than cursors DPI!!!    cursor.currentCursorDevicePixelRatio=${cursor.currentCursorDevicePixelRatio} != currentDevicePixelRatio=$currentDevicePixelRatio');
        }
        if (cursor.switchToCachedDevicePixelRatioIfPossible(currentDevicePixelRatio)) {
          continue;
        }
        await cursor._updateCursorToNewDpr(currentDevicePixelRatio);
      }
    }
    _lastEnsuredDevicePixelRatio = currentDevicePixelRatio;
    if (_Logger.logging) {
      _Logger.log('  LEAVING ensurePointersMatchDevicePixelRatio()!!!!!');
    }
  }

  /// Our onMetricsChanged() callback.
  static void onMetricsChanged() {
    ensurePointersMatchDevicePixelRatio(null);
  }

  /// If a context is supplied then [createLocalImageConfiguration] is used as
  /// normal to create the [ImageConfiguration] object.  Otherwise the
  /// devicePixelRatio from [PlatformDispatcher] is used (or the
  /// [forceDevicePixelRatio] value) to create an ImageConfiguration().
  static ImageConfiguration _createLocalImageConfigurationWithOrWithoutContext(
      {BuildContext? context, double? forceDevicePixelRatio}) {
    if (forceDevicePixelRatio != null || context == null) {
      final ImageConfiguration returnImageConfiguration = ImageConfiguration(
        bundle: rootBundle,
        devicePixelRatio: forceDevicePixelRatio ?? _getDevicePixelRatioFromView(),
        locale: PlatformDispatcher.instance.locale,
        textDirection: TextDirection.ltr,
        size: null,
        platform: defaultTargetPlatform,
      );
      if (forceDevicePixelRatio == null) {
        // ONLY REMEMBER THIS AS [_lastImageConfiguration] if it was NOT FORCED
        _lastImageConfiguration = returnImageConfiguration;
      }
      return returnImageConfiguration;
    } else {
      _lastImageConfiguration = createLocalImageConfiguration(context);
      return _lastImageConfiguration!;
    }
  }

  static bool _noOnMetricsChangedHook = false;

  /// This method allows user to specify that they don't want us to hook the
  /// onMetricsChanged() — if we hook it then it will conflict with user's hook,
  /// so we must provide way to opt out.  If user opts out they must MANUALLY
  /// call `CustomMouseCursor.ensurePointersMatchDevicePixelRatio(context)`.
  static set noOnMetricsChangedHook(bool newVal) {
    if (!_noOnMetricsChangedHook && newVal && _onMetricChangedCallbackSet) {
      throw ('CustomMouseCursor already hooked onMetricsChanged() - set noOnMetricsChangedHook BEFORE creating cursors');
    }
    _noOnMetricsChangedHook = newVal;
  }

  static bool get noOnMetricsChangedHook {
    return _noOnMetricsChangedHook && !_onMetricChangedCallbackSet;
  }

  static bool _onMetricChangedCallbackSet = false;

  /// Get current devicePixelRatio from PlatformDispatcher.implicitView.
  static double _getCurrentDevicePixelRatioFromWindow() {
    final FlutterView? view = PlatformDispatcher.instance.implicitView;
    if (view == null) {
      throw ('CustomMouseCursor detected null PlatformDispatcher.instance.implicitView — multiple window environments are not yet supported.');
    }
    return view.devicePixelRatio;
  }

  /// Get current devicePixelRatio from either [_lastImageConfiguration] or
  /// from the PlatformDispatcher.
  static double _getCurrentDevicePixelRatioFromLastConfigOrWindow() {
    if (_lastImageConfiguration != null && _lastImageConfiguration!.devicePixelRatio != null) {
      return _lastImageConfiguration!.devicePixelRatio!;
    }
    return _getCurrentDevicePixelRatioFromWindow();
  }

  /// Various ways of getting current DevicePixelRatio.
  static double _getDevicePixelRatioFromView() {
    return _getCurrentDevicePixelRatioFromWindow();
  }

  /// We hook into the system's onMetricsChanged() callback.
  static void _setupViewsOnMetricChangedCallbacks() {
    if (!_onMetricChangedCallbackSet && !_noOnMetricsChangedHook) {
      _onMetricChangedCallbackSet = true;
      if (_Logger.logging) {
        _Logger.log(('setupViewsOnMetricChangedCallbacks() called and BEING SET UP'));
      }
      final VoidCallback? existedBeforeUsOnMetricsChanged = WidgetsBinding.instance.platformDispatcher.onMetricsChanged;
      WidgetsBinding.instance.platformDispatcher.onMetricsChanged = () {
        if (_Logger.hookLogging) {
          _Logger.log(
              'CustomMouseCursor.onMetricsChanged() platformDispatcher() version!!!!! existedBeforeUsOnMetricsChanged=$existedBeforeUsOnMetricsChanged');
        }
        if (existedBeforeUsOnMetricsChanged != null) {
          existedBeforeUsOnMetricsChanged.call();
        }
        onMetricsChanged();
      };
    }
  }

  static math.Random? randomGenerator;

  /// Generate a 16 digit random key to use for cursor's key.
  static String generateUniqueKey() {
    randomGenerator ??= math.Random(DateTime.now().microsecond);

    const String hexDigits = "0123456789abcdef";
    final List<String> uuid = List<String>.filled(16, '');

    for (int i = 0; i < 16; i++) {
      final int hexPos = randomGenerator!.nextInt(16);
      uuid[i] = hexDigits.substring(hexPos, hexPos + 1);
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeAll(uuid);
    return buffer.toString();
  }

  /// Converts the uiImage to a Uint8List in BGRA format (required by Windows).
  static Future<Uint8List> _getBytesAsBGRAFromImage(ui.Image image) async {
    final int width = image.width;
    final int height = image.height;
    final ByteData? rgbaBD = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgbaBD == null) {
      throw ('Error converting ui.Image to rawRgba byte data');
    }
    final Uint8List rgba = rgbaBD.buffer.asUint8List();
    return _getRGBABytesAsBGRA(rgba, width, height);
  }

  /// Convert RGBA formatted Uint8List into BGRA format.
  /// (This format is needed for creating cursors on windows platform)
  static Uint8List _getRGBABytesAsBGRA(Uint8List rgba, int width, int height) {
    final int length = width * height * 4;
    assert(rgba.lengthInBytes == length && rgba.lengthInBytes % 4 == 0);
    final Uint8List bgra = Uint8List(length);
    for (int i = 0; i < length; i += 4) {
      bgra[i + 0] = rgba[i + 2];
      bgra[i + 1] = rgba[i + 1];
      bgra[i + 2] = rgba[i + 0];
      bgra[i + 3] = rgba[i + 3];
    }
    return bgra;
  }

  /// Creates an image from the specified icon.  This is essentially identical
  /// parameters to the Icon() flutter widget but creates a ui.Image instead.
  static ui.Image _createImageFromIconSync(
    IconData icon, {
    double size = 32,
    Color color = Colors.black,
    double? iconFill,
    double? iconWeight,
    double? iconGrade,
    double? iconOpticalSize,
    List<Shadow>? shadows,
  }) {
    final PictureRecorder recorder = PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final TextSpan textSpan = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontVariations: <FontVariation>[
          if (iconFill != null) FontVariation('FILL', iconFill),
          if (iconWeight != null) FontVariation('wght', iconWeight),
          if (iconGrade != null) FontVariation('GRAD', iconGrade),
          if (iconOpticalSize != null) FontVariation('opsz', iconOpticalSize),
        ],
        inherit: false,
        color: color,
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        shadows: shadows,
      ),
    );

    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset.zero);

    final Picture picture = recorder.endRecording();

    late final ui.Image uiimage;
    try {
      uiimage = picture.toImageSync(
        size.floor(),
        size.floor(),
      );
    } finally {
      picture.dispose();
    }
    return uiimage;
  }

  /// Decode a PNG Uint8List buffer and possibly scale it as well (if
  /// [rescaleRatioRequiredForImage]!=1.0) during the decoding process.
  static Future<ui.Image> _createUIImageFromPNGUint8ListBufferAndPossiblyScale(
    Uint8List rawUint8, {
    double rescaleRatioRequiredForImage = 1.0,
  }) async {
    if (rescaleRatioRequiredForImage == 1.0) {
      return await decodeImageFromList(rawUint8);
    }

    final ui.Codec codec = await PaintingBinding.instance.instantiateImageCodecWithSize(
      await ImmutableBuffer.fromUint8List(rawUint8),
      getTargetSize: (int width, int height) {
        return TargetImageSize(
          width: (width * rescaleRatioRequiredForImage).round(),
          height: (height * rescaleRatioRequiredForImage).round(),
        );
      },
    );
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
}

class _CustomMouseCursorSession extends MouseCursorSession {
  _CustomMouseCursorSession(CustomMouseCursor super.cursor, super.device);

  @override
  CustomMouseCursor get cursor => super.cursor as CustomMouseCursor;

  @override
  Future<void> activate() async {
    if (cursor.isValid) {
      await _CustomMouseCursorPlatformInterface.setSystemCursor(cursor.key);
    } else {
      throw ('An attempt to use a CustomMouseCursor object (${cursor.key}) which previously had dispose() called.');
    }
  }

  @override
  void dispose() {}
}

/// The platform interface for Windows.  Uses the flutter engine's built-in
/// `SystemChannels.mouseCursor` channel which accepts commands in the
/// `createCustomCursor/windows`, `setCustomCursor/windows`, and
/// `deleteCustomCursor/windows` format.
class _CustomMouseCursorPlatformInterface {
  static const String createCursorKey = "createCustomCursor";
  static const String setCursorMethod = "setCustomCursor";
  static const String deleteCursorMethod = "deleteCustomCursor";

  _CustomMouseCursorPlatformInterface._();

  static Future<String> registerCursor(
    String name,
    Uint8List buffer,
    int width,
    int height,
    double hotX,
    double hotY,
  ) async {
    final String? cursorName = await SystemChannels.mouseCursor.invokeMethod<String>(
      '$createCursorKey/windows',
      <String, dynamic>{
        'name': name,
        'buffer': buffer,
        'width': width,
        'height': height,
        'hotX': hotX,
        'hotY': hotY,
      },
    );
    assert(cursorName == name);
    return cursorName!;
  }

  static Future<void> deleteCursor(String name) async {
    await SystemChannels.mouseCursor.invokeMethod('$deleteCursorMethod/windows', <String, String>{"name": name});
  }

  static Future<void> setSystemCursor(String name) async {
    await SystemChannels.mouseCursor.invokeMethod('$setCursorMethod/windows', <String, String>{"name": name});
  }
}

enum _CustomMouseCursorCreationType { exactasset, asset, image, icon }

/// This class is used to remember the parameters originally passed to icon()
/// method so regeneration of the icon based cursor's image is possible when the
/// devicePixelRatio changes.
class _CustomMouseCursorFromIconOriginInfo {
  _CustomMouseCursorFromIconOriginInfo({
    required this.icon,
    required this.sizeInLogicalPixels,
    required this.hotXInLogicalPixels,
    required this.hotYInLogicalPixels,
    required this.fill,
    required this.weight,
    required this.opticalSize,
    required this.grade,
    required this.color,
    required this.shadows,
  });
  final double sizeInLogicalPixels;
  final int hotXInLogicalPixels;
  final int hotYInLogicalPixels;
  final IconData icon;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final Color color;
  final List<Shadow>? shadows;
}

/// This is used to cache information about images used by already created
/// cursors for a specific DevicePixelRatio.  This allows us to skip
/// re-loading/creation of bitmaps for a given DPR when the flutter window
/// moves between different DPR screens.  Instead the system cursor can be
/// regenerated from the cached bitmap data within [imageBuffer].
class _CustomMouseCursorDPRBitmapCache {
  const _CustomMouseCursorDPRBitmapCache(
    this.imageBuffer,
    this.width,
    this.height,
    this.hotX,
    this.hotY,
  );
  final Uint8List imageBuffer;
  final int width;
  final int height;
  final int hotX;
  final int hotY;
}
