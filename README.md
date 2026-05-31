# docOCR

`docOCR` is a macOS command-line OCR tool that converts document images into Markdown text. It can run as a batch CLI tool or as a local HTTP server for browser uploads and API clients.

![Image](image.png)

## Features

- Converts image files to Markdown text.
- Writes batch OCR output next to each source image using the same basename and a `.md` extension.
- Converts detected paragraphs, lists, and tables into Markdown when Apple's document recognition API identifies them.
- Provides a local web UI for uploading an image and viewing OCR output.
- Provides a JSON API for image upload and OCR response.
- Uses Apple's `RecognizeDocumentsRequest` API, available on macOS 26+.
- Performs OCR locally on the Mac. OCR recognition does not require sending images to an external network service.

The HTTP server is implemented with Vapor.

## Requirements

- macOS 26 or later.
- Xcode / Swift toolchain that supports the package's Swift tools version.
- Network access may be required during the first build so Swift Package Manager can fetch dependencies such as Vapor.

## CLI Usage

Show help:

```bash
docOCR -h
docOCR --help
```

Show version:

```bash
docOCR -V
docOCR --version
```

Convert image files to Markdown:

```bash
docOCR -o ~/Desktop/book_imgs/*.jpg
```

Each input file is written as a Markdown file next to the image:

```text
~/Desktop/book_imgs/01.jpg -> ~/Desktop/book_imgs/01.md
~/Desktop/book_imgs/02.jpg -> ~/Desktop/book_imgs/02.md
```

Existing `.md` files with the same name are overwritten.

Start the HTTP server:

```bash
docOCR -s
```

By default, the server listens on port `8080`.

Use a custom port:

```bash
docOCR -s -p 8000
```

The `-s` and `-o` modes are mutually exclusive.

## HTTP Server

When the server is running, open:

```text
http://0.0.0.0:8080
```

If you start the server with a custom port, use that port instead:

```text
http://0.0.0.0:8000
```

The web page uses:

```text
POST /upload
```

This route is intended for browser form uploads and returns an HTML result page.

## API Usage

Use the JSON API endpoint:

```text
POST /api/ocr
```

Example:

```bash
curl -X POST http://127.0.0.1:8000/api/ocr \
  -F "file=@01.png"
```

The API also accepts `image` as the multipart field name:

```bash
curl -X POST http://127.0.0.1:8000/api/ocr \
  -F "image=@01.png"
```

Successful response:

```json
{
  "success": true,
  "message": "OK",
  "text": "OCR text..."
}
```

Error response:

```json
{
  "success": false,
  "message": "Error message",
  "text": ""
}
```

## Build

Build a debug executable:

```bash
swift build
```

Build a release executable:

```bash
swift build -c release
```

The release binary is generated at:

```text
.build/release/docOCR
```

## Install

Build the release binary:

```bash
swift build -c release
```

Install it somewhere on your `PATH`, for example:

```bash
install -m 755 .build/release/docOCR /usr/local/bin/docOCR
```

Then run:

```bash
docOCR -h
```

If `/usr/local/bin` is not writable or not on your `PATH`, choose another directory such as `~/bin` and make sure that directory is included in your shell `PATH`.

## Development

Run directly with SwiftPM:

```bash
swift run docOCR -o ~/Desktop/book_imgs/*.jpg
swift run docOCR -s -p 8000
```

## macOS Shortcuts: Screenshot to Markdown

`docOCR` can also be used with the Shortcuts app on macOS to turn a screenshot into Markdown text.

In this workflow, the shortcut captures a screen selection, sends the screenshot image to the local `docOCR` HTTP API, copies the OCR Markdown text to the clipboard, and then lets you paste the result into any text editor.

Start the local server first:

```bash
docOCR -s
```

Then run the macOS shortcut:

![screenshot_to_md](screenshot_to_md.gif)

The shortcut flow is:

1. Capture a screenshot.
2. Upload the image to `http://127.0.0.1:8080/api/ocr`.
3. Read the `text` field from the JSON response.
4. Copy the Markdown text to the clipboard.

Paste the result into your editor.

![image2](image2.png)

## Codex Skill

If you use Codex, you can install the companion skill for docOCR: [dococr-skill](https://github.com/riddleling/dococr-skill)

The skill gives Codex reusable context for docOCR CLI usage, local HTTP API calls, OCR execution, and troubleshooting.
