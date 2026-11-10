import Foundation

private struct HuggingFaceModelInfo: Decodable, Sendable {
    struct Sibling: Decodable, Sendable {
        let rfilename: String
        let size: Int64?
    }

    let siblings: [Sibling]
}

actor ResumableModelDownloader {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(
        modelID: String,
        to directory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let marker = directory.appendingPathComponent(".download-complete")
        if FileManager.default.fileExists(atPath: marker.path) {
            progress(1)
            return
        }
        guard let infoURL = URL(string: "https://huggingface.co/api/models/\(modelID)?blobs=true") else {
            throw URLError(.badURL)
        }
        let (infoData, infoResponse) = try await session.data(from: infoURL)
        guard let http = infoResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let siblings = try JSONDecoder().decode(HuggingFaceModelInfo.self, from: infoData).siblings
            .filter { $0.rfilename.hasSuffix(".json") || $0.rfilename.hasSuffix(".safetensors") }
        guard !siblings.isEmpty else { throw URLError(.resourceUnavailable) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await download(siblings, modelID: modelID, to: directory, progress: progress)
        try Data(modelID.utf8).write(to: marker, options: .atomic)
        progress(1)
    }

    private func download(
        _ siblings: [HuggingFaceModelInfo.Sibling],
        modelID: String,
        to directory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let knownTotal = siblings.compactMap(\.size).reduce(0, +)
        var completedKnownBytes: Int64 = 0
        for (index, sibling) in siblings.enumerated() {
            try Task.checkCancellation()
            guard !sibling.rfilename.contains("..") else { throw URLError(.badURL) }
            let destination = directory.appendingPathComponent(sibling.rfilename)
            if FileManager.default.fileExists(atPath: destination.path) {
                completedKnownBytes += sibling.size ?? 0
                continue
            }
            let downloaded = try await download(
                sibling,
                modelID: modelID,
                to: destination,
                index: index,
                fileCount: siblings.count,
                completedBytes: completedKnownBytes,
                totalBytes: knownTotal,
                progress: progress
            )
            completedKnownBytes += sibling.size ?? downloaded
        }
    }

    private func download(
        _ sibling: HuggingFaceModelInfo.Sibling,
        modelID: String,
        to destination: URL,
        index: Int,
        fileCount: Int,
        completedBytes: Int64,
        totalBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let partial = destination.appendingPathExtension("partial")
        let existing = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard let url = URL(string: "https://huggingface.co/\(modelID)/resolve/main/\(sibling.rfilename)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 || response.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }
        if !FileManager.default.fileExists(atPath: partial.path) {
            _ = FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let downloaded = try await write(
            bytes,
            response: response,
            partial: partial,
            existing: existing,
            progressDetails: (index, fileCount, completedBytes, totalBytes, progress)
        )
        try FileManager.default.moveItem(at: partial, to: destination)
        reportProgress(
            index: index + 1,
            fileCount: fileCount,
            completedBytes: completedBytes + (sibling.size ?? downloaded),
            currentBytes: 0,
            totalBytes: totalBytes,
            progress: progress
        )
        return downloaded
    }

    private func write(
        _ bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse,
        partial: URL,
        existing: Int64,
        progressDetails: (Int, Int, Int64, Int64, @Sendable (Double) -> Void)
    ) async throws -> Int64 {
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        var downloaded: Int64
        if response.statusCode == 206 {
            try handle.seekToEnd()
            downloaded = existing
        } else {
            try handle.truncate(atOffset: 0)
            downloaded = 0
        }
        var buffer = Data()
        buffer.reserveCapacity(1_048_576)
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 1_048_576 {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                reportProgress(
                    index: progressDetails.0,
                    fileCount: progressDetails.1,
                    completedBytes: progressDetails.2,
                    currentBytes: downloaded,
                    totalBytes: progressDetails.3,
                    progress: progressDetails.4
                )
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
        }
        try handle.synchronize()
        return downloaded
    }

    private func reportProgress(
        index: Int,
        fileCount: Int,
        completedBytes: Int64,
        currentBytes: Int64,
        totalBytes: Int64,
        progress: @Sendable (Double) -> Void
    ) {
        if totalBytes > 0 {
            progress(min(Double(completedBytes + currentBytes) / Double(totalBytes), 1))
        } else {
            progress(min(Double(index) / Double(fileCount), 1))
        }
    }
}
