# Background Remover — Tabame plugin

Keyword: `bgremove`

## Install

Copy this folder to:

```text
%localappdata%\Tabame\plugins\background-remover\
```

Reopen the Tabame launcher. Tabame installs `rembg[cpu]` into the plugin's
private dependency folder on first launch. The selected model is downloaded
only when you first use it and is kept in this plugin's `models` folder.

## Use

- Type `bgremove` and choose **Choose an image**, or type/paste an image path
  after the keyword.
- Choose **BiRefNet** or **BRIA RMBG 2.0**. Enter on a model downloads it if
  needed, loads it, and opens the removal settings.
- Configure the output format, output folder, suffix, background mode, mask
  post-processing, alpha matting thresholds, cropping, and optional mask
  export.
- Enter **Remove background**. The result view can open the output, reveal its
  folder, copy its path, or run another image.

## Models and licenses

The plugin uses rembg's local ONNX sessions:

- `birefnet-general` → [ZhengPeng7/BiRefNet](https://huggingface.co/ZhengPeng7/BiRefNet)
  (MIT)
- `bria-rmbg` → [briaai/RMBG-2.0](https://huggingface.co/briaai/RMBG-2.0)
  (BRIA RMBG 2.0, CC BY-NC 4.0 for non-commercial use)

Check the model licenses before using the plugin commercially. BRIA's
self-hosted weights require a separate commercial agreement for commercial
use.

## Notes

- This version uses the CPU ONNX backend. If `onnxruntime-gpu` is installed
  separately, the settings form can use a CUDA execution provider.
- The first model download can be large and CPU inference can take a while;
  Tabame shows a loading frame while the work runs.
- Set `"dev": true` in `plugin.json` while developing, then set it back to
  `false` before sharing the plugin.
