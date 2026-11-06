# Slow Reading: OCR for Researchers

A Mac app that transcribes scanned pages and PDFs with the [olmOCR 2](https://huggingface.co/allenai/olmOCR-2-7B-1025) model. Drop in a PDF, an image or a folder of images and get a Markdown transcript. Everything runs on your own Mac: the model is downloaded once, and your documents are never sent anywhere.

It is built for historians and other researchers who have scans, not a terminal.

## Requirements

- A Mac with Apple Silicon (M1 or later) and macOS 14 or newer
- 16 GB of memory or more
- About 5 GB of free disk space for the Compact model, or about 9 GB for the Full model

## Installing

1. Download the latest `Slow-Reading-*.zip` from [Releases](https://github.com/poskett/slow-reading-ocr/releases) and unzip it.
2. Move **Slow Reading** to your Applications folder.
3. The app is not signed with an Apple developer certificate, so macOS blocks it the first time. Try to open it, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
4. On first launch the app downloads a model from Hugging Face. Compact is smaller and faster. Full is more accurate and needs more memory.

## Using it

Drop PDFs, images or folders onto the window, then press **Start**. Everything is saved in a `_transcript` folder next to the original, or in a folder you choose in Settings: the whole transcript as a `.md` file, plus one file per page. The queue comes back when you reopen the app, and finished documents stay in it until you remove them. Right-click a document to clear finished items or transcribe it again.

- Pages are read at the resolution olmOCR expects, with up to eight attempts per page at rising temperatures, and rotation is corrected where the model asks for it.
- A page that could not be read cleanly is marked `NEEDS CHECKING` in the transcript and flagged in the app. For PDFs with a text layer, that text is used as a fallback.
- Settings can also write plain text, JSONL and a CSV manifest recording the model, settings and status of every page. One file per page can be turned off there.
- The app can check once a day for a new version and for changes to the model repository. This can be turned off in Settings.

## Removing models and uninstalling

Models and cached pages are kept in `~/Library/Application Support/Slow Reading`. Open **Settings → Storage** to remove a model, clear the cached pages, or open that folder in Finder. The app also keeps a copy of the transcribed text there until you remove a document from the queue and clear the cached pages. Your transcripts are saved elsewhere and are never touched.

To uninstall, remove the models first if you want the disk space back, then delete **Slow Reading** from your Applications folder.

## Building from source

You need Xcode (not only the command line tools).

```
scripts/build_app.sh
```

This builds `build/Slow Reading.app`. The same code also builds a command-line tool, `olmocr`, which takes the same options (`olmocr --help`). Build with `xcodebuild`, as the script does, rather than `swift build`, because the MLX Metal shaders need Xcode's build system.

`Sources/OlmOCRCore` holds the reading, retrying and exporting code, and `Sources/OlmOCRApp` holds the interface. `scripts/make_icon.swift` draws the icon.

## Credits and licences

- This app and its source code: MIT licence (see `LICENSE`).
- olmOCR 2 model by [Ai2](https://allenai.org), based on Qwen2.5-VL: Apache 2.0. The app downloads MLX conversions published by [mlx-community](https://huggingface.co/mlx-community).
- [MLX](https://github.com/ml-explore/mlx-swift) by Apple: MIT.
- The sample page in the app is from an 1838 issue of the American Phrenological Journal.
- Code generated using Anthropic Claude. Project developed by James Poskett (University of Warwick).
