import Foundation

@main
struct docOCR {
    static func main() async {
        do {
            let command = try OCRCommand(arguments: Array(CommandLine.arguments.dropFirst()))
            try await command.run()
        } catch {
            FileHandle.standardError.writeLine(error.localizedDescription)
            FileHandle.standardError.writeLine(OCRCommand.usage)
            Foundation.exit(1)
        }
    }
}

struct OCRCommand {
    static let version = AppVersion.current
    static let usage = """
    Usage:
      docOCR <image1.jpg> [image2.jpg ...]
      docOCR -o <image1.jpg> [image2.jpg ...]
      docOCR -s [-p <port>]

    Options:
      <images...>       OCR image files and print Markdown to stdout
      -o <images...>    OCR image files and write .md files next to them
      -s                Start the HTTP server
      -p <port>         HTTP server port, only valid with -s
      -h, --help        Show help
      -V, --version     Show version
    """

    private let mode: Mode

    init(arguments: [String], ocrService: DocumentOCRService = DocumentOCRService()) throws {
        let parsedArguments = try ParsedArguments(arguments)

        if parsedArguments.helpRequested {
            mode = .help
            return
        }

        if parsedArguments.versionRequested {
            mode = .version
            return
        }

        switch (
            parsedArguments.serverEnabled,
            parsedArguments.outputImagePaths.isEmpty,
            parsedArguments.inputImagePaths.isEmpty
        ) {
        case (true, true, true):
            mode = .server(port: parsedArguments.port, ocrService: ocrService)
        case (false, false, true):
            guard parsedArguments.port == nil else {
                throw OCRCommandError.portRequiresServerMode
            }

            mode = .outputFiles(
                imageURLs: parsedArguments.outputImagePaths.map {
                    URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath)
                },
                ocrService: ocrService
            )
        case (false, true, false):
            guard parsedArguments.port == nil else {
                throw OCRCommandError.portRequiresServerMode
            }

            mode = .printText(
                imageURLs: parsedArguments.inputImagePaths.map {
                    URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath)
                },
                ocrService: ocrService
            )
        default:
            throw OCRCommandError.invalidArguments
        }
    }

    func run() async throws {
        switch mode {
        case .help:
            print(Self.usage)
        case .version:
            print(Self.version)
        case .outputFiles(let imageURLs, let ocrService):
            for imageURL in imageURLs {
                try await processImage(at: imageURL, ocrService: ocrService)
            }
        case .printText(let imageURLs, let ocrService):
            for (index, imageURL) in imageURLs.enumerated() {
                let markdownText = try await recognizeImage(at: imageURL, ocrService: ocrService)
                if index > 0 {
                    print("")
                }

                print(markdownText)
            }
        case .server(let port, let ocrService):
            try await DocumentOCRHTTPServer(port: port, ocrService: ocrService).run()
        }
    }

    private func processImage(at imageURL: URL, ocrService: DocumentOCRService) async throws {
        let markdownText = try await recognizeImage(at: imageURL, ocrService: ocrService)
        let outputURL = imageURL.deletingPathExtension().appendingPathExtension("md")

        do {
            try markdownText.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw OCRCommandError.cannotWriteMarkdown(outputURL.path)
        }

        print("Wrote \(outputURL.path)")
    }

    private func recognizeImage(at imageURL: URL, ocrService: DocumentOCRService) async throws -> String {
        let imageData: Data

        do {
            imageData = try Data(contentsOf: imageURL)
        } catch {
            throw OCRCommandError.cannotReadImage(imageURL.path)
        }

        return try await ocrService.recognizeParagraphText(from: imageData)
    }
}

private enum Mode {
    case help
    case version
    case printText(imageURLs: [URL], ocrService: DocumentOCRService)
    case outputFiles(imageURLs: [URL], ocrService: DocumentOCRService)
    case server(port: Int?, ocrService: DocumentOCRService)
}

private struct ParsedArguments {
    var helpRequested = false
    var versionRequested = false
    var serverEnabled = false
    var port: Int?
    var inputImagePaths: [String] = []
    var outputImagePaths: [String] = []

    init(_ arguments: [String]) throws {
        if arguments == ["-h"] || arguments == ["--help"] {
            helpRequested = true
            return
        }

        if arguments == ["-V"] || arguments == ["--version"] {
            versionRequested = true
            return
        }

        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]

            switch argument {
            case "-h", "--help":
                throw OCRCommandError.helpMustBeUsedAlone
            case "-V", "--version":
                throw OCRCommandError.versionMustBeUsedAlone
            case "-s":
                guard !serverEnabled else {
                    throw OCRCommandError.invalidArguments
                }

                serverEnabled = true
                index = arguments.index(after: index)
            case "-p":
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex,
                      let portValue = Int(arguments[valueIndex]),
                      (1...65535).contains(portValue) else {
                    throw OCRCommandError.invalidPort
                }

                port = portValue
                index = arguments.index(after: valueIndex)
            case "-o":
                let firstImageIndex = arguments.index(after: index)
                guard firstImageIndex < arguments.endIndex else {
                    throw OCRCommandError.noInputImages
                }

                outputImagePaths = Array(arguments[firstImageIndex...])
                guard !outputImagePaths.contains(where: { $0 == "-s" || $0 == "-p" || $0 == "-o" }) else {
                    throw OCRCommandError.invalidArguments
                }

                index = arguments.endIndex
            default:
                guard !argument.hasPrefix("-") else {
                    throw OCRCommandError.invalidArguments
                }

                inputImagePaths = Array(arguments[index...])
                guard !inputImagePaths.contains(where: { $0 == "-s" || $0 == "-p" || $0 == "-o" }) else {
                    throw OCRCommandError.invalidArguments
                }

                index = arguments.endIndex
            }
        }

        if serverEnabled, !outputImagePaths.isEmpty {
            throw OCRCommandError.mutuallyExclusiveModes
        }

        if serverEnabled, !inputImagePaths.isEmpty {
            throw OCRCommandError.mutuallyExclusiveModes
        }

        if !outputImagePaths.isEmpty, !inputImagePaths.isEmpty {
            throw OCRCommandError.mutuallyExclusiveModes
        }
    }
}

enum OCRCommandError: LocalizedError {
    case invalidArguments
    case helpMustBeUsedAlone
    case versionMustBeUsedAlone
    case noInputImages
    case mutuallyExclusiveModes
    case portRequiresServerMode
    case invalidPort
    case cannotReadImage(String)
    case cannotWriteMarkdown(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "Invalid arguments"
        case .helpMustBeUsedAlone:
            "-h/--help cannot be used with other arguments"
        case .versionMustBeUsedAlone:
            "-V/--version cannot be used with other arguments"
        case .noInputImages:
            "Specify at least one image file after -o"
        case .mutuallyExclusiveModes:
            "-s and -o cannot be used together"
        case .portRequiresServerMode:
            "-p can only be used with -s"
        case .invalidPort:
            "Specify a port between 1 and 65535 after -p"
        case .cannotReadImage(let path):
            "Cannot read image: \(path)"
        case .cannotWriteMarkdown(let path):
            "Cannot write Markdown: \(path)"
        }
    }
}

private extension FileHandle {
    func writeLine(_ text: String) {
        guard let data = "\(text)\n".data(using: .utf8) else {
            return
        }

        write(data)
    }
}
