import Foundation

public struct FileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

public enum FileService {
    public static func identity(of url: URL) throws -> FileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        guard let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber else { throw CompressionError.unreadablePDF }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }

    public static func save(result: CompressionResult, to destination: URL, originalURL: URL,
                            originalIdentity: FileIdentity? = nil) throws {
        let protectedIdentity = originalIdentity ?? (try? identity(of: originalURL))
        guard destination.isFileURL, destination.pathExtension.lowercased() == "pdf" else { throw CompressionError.cannotWriteOutput }
        guard !sameFile(destination, originalURL), !sameFile(destination, result.sourceURL),
              !sameFile(destination, result.outputURL),
              protectedIdentity == nil || (try? identity(of: destination)) != protectedIdentity else {
            throw CompressionError.cannotOverwriteOriginal
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.copyItem(at: result.outputURL, to: staging)
            // Recheck identity after staging so a renamed original cannot be replaced during the copy.
            guard !sameFile(destination, originalURL), !sameFile(destination, result.sourceURL),
                  protectedIdentity == nil || (try? identity(of: destination)) != protectedIdentity else {
                throw CompressionError.cannotOverwriteOriginal
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else { try FileManager.default.moveItem(at: staging, to: destination) }
        } catch let error as CompressionError { throw error }
        catch { throw writeError(error) }
    }

    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath() { return true }
        guard let a = try? identity(of: lhs), let b = try? identity(of: rhs) else { return false }
        return a == b
    }

    static func writeError(_ error: Error) -> CompressionError {
        let error = error as NSError
        if (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError) ||
           (error.domain == NSPOSIXErrorDomain && error.code == 28) { return .insufficientDiskSpace }
        return .cannotWriteOutput
    }
}
