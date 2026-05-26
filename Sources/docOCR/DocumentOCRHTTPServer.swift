import Foundation
import Vapor

struct DocumentOCRHTTPServer {
    private let hostname = "0.0.0.0"
    private let port: Int
    private let ocrService: DocumentOCRService

    init(port: Int?, ocrService: DocumentOCRService) {
        self.port = port ?? 8080
        self.ocrService = ocrService
    }

    func run() async throws {
        let app = try await Application.make(.init(name: "development", arguments: ["docOCR"]))

        app.http.server.configuration.hostname = hostname
        app.http.server.configuration.port = port
        app.routes.defaultMaxBodySize = "30mb"
        app.middleware.use(APIErrorMiddleware())

        app.get { _ in
            htmlResponse(uploadPageHTML(port: port))
        }

        app.post("upload") { request async throws -> Response in
            let upload = try request.content.decode(ImageUpload.self)
            let text = try await ocrService.recognizeParagraphText(from: try upload.imageData())
            return htmlResponse(resultPageHTML(text: text))
        }

        app.post("api", "ocr") { request async throws -> OCRResponse in
            let upload = try request.content.decode(ImageUpload.self)
            let text = try await ocrService.recognizeParagraphText(from: try upload.imageData())
            return OCRResponse(success: true, message: "OK", text: text)
        }

        do {
            try await app.execute()
            try await app.asyncShutdown()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
    }

    private func uploadPageHTML(port: Int) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>docOCR</title>
            <style>
                body { font-family: Arial, Helvetica, sans-serif; margin: 0; color: #000; background: #fff; }
                main { padding: 40px 16px 64px; }
                h1 { font-size: 2rem; line-height: 1.2; margin: 0 0 32px; font-weight: 700; }
                h2 { font-size: 1.4rem; line-height: 1.25; margin: 0 0 20px; font-weight: 700; }
                p { font-size: 1.1rem; line-height: 1.4; margin: 0 0 16px; font-weight: 700; }
                code { background: #ddd; border-radius: 6px; padding: 4px 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
                pre { box-sizing: border-box; width: 100%; margin: 0 0 24px; padding: 24px 28px; border-radius: 8px; background: #ddd; overflow-x: auto; }
                pre code { display: block; padding: 0; background: transparent; border-radius: 0; font-size: 1rem; line-height: 1.4; white-space: pre; }
                hr { border: 0; border-top: 1px solid #aaa; margin: 24px 0 32px; }
                form { display: grid; gap: 24px; justify-items: start; }
                label { font-size: 1rem; }
                input, button { font: inherit; font-size: 1rem; }
                button { padding: 4px 12px; }
            </style>
        </head>
        <body>
            <main>
                <h1>docOCR</h1>
                <p>Upload an image via <code>/api/ocr</code> API:</p>
                <pre><code>curl -H "Accept: application/json" \\
          -X POST http://&lt;YOUR IP&gt;:\(port)/api/ocr \\
          -F "file=@01.png"</code></pre>
                <hr>
                <h2>OCR Test:</h2>
                <form method="post" action="/upload" enctype="multipart/form-data">
                    <label>Choose file: <input type="file" name="file" accept="image/*" required></label>
                    <button type="submit">Upload file</button>
                </form>
            </main>
        </body>
        </html>
        """
    }

    private func resultPageHTML(text: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>docOCR Result</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 40px; line-height: 1.5; }
                main { max-width: 960px; }
                textarea { box-sizing: border-box; width: 100%; min-height: 520px; font: 15px ui-monospace, SFMono-Regular, Menlo, monospace; line-height: 1.5; padding: 12px; }
                a { display: inline-block; margin-bottom: 16px; }
            </style>
        </head>
        <body>
            <main>
                <a href="/">Upload another image</a>
                <textarea readonly>\(text.htmlEscaped)</textarea>
            </main>
        </body>
        </html>
        """
    }
}

private struct ImageUpload: Content {
    let file: File?
    let image: File?

    func imageData() throws -> Data {
        Data(try uploadedFile.data.readableBytesView)
    }

    private var uploadedFile: File {
        get throws {
            if let file {
                return file
            }

            if let image {
                return image
            }

            throw Abort(.badRequest, reason: "Missing multipart file field. Use `file`.")
        }
    }
}

private struct OCRResponse: Content {
    let success: Bool
    let message: String
    let text: String
}

private struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            guard request.url.path.hasPrefix("/api/") else {
                throw error
            }

            let status: HTTPResponseStatus
            let message: String

            if let abortError = error as? AbortError {
                status = abortError.status
                message = abortError.reason
            } else {
                status = .internalServerError
                message = error.localizedDescription
            }

            let response = OCRResponse(success: false, message: message, text: "")
            let data = try JSONEncoder().encode(response)
            return Response(
                status: status,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: .init(data: data)
            )
        }
    }
}

private func htmlResponse(_ html: String) -> Response {
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "text/html; charset=utf-8")
    return Response(status: .ok, headers: headers, body: .init(string: html))
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
