import Foundation

private func calcHash(_ key: Data) -> UInt32 {
  var hash: UInt32 = 5381
  for byte in key {
    hash = ((hash << 5) &+ hash) ^ UInt32(byte)
  }
  return hash
}

public class CDBReader {
  let fileHandle: FileHandle
  let posHeader: UInt64

  public init(filePath: String, posHeader: UInt64) throws {
    self.fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
    self.posHeader = posHeader
  }

  deinit {
    fileHandle.closeFile()
  }

  private func readUInt32(offset: UInt64) -> UInt32 {
    fileHandle.seek(toFileOffset: offset)
    let data = fileHandle.readData(ofLength: 4)
    return data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
  }

  public func cdbget(key: String) throws -> Data {
    let keyData = key.data(using: .utf8)!
    let h = calcHash(keyData)

    fileHandle.seek(toFileOffset: posHeader + UInt64((h % 256) * 8))
    let posBucket = readUInt32(offset: fileHandle.offsetInFile)
    let ncells = readUInt32(offset: fileHandle.offsetInFile)

    guard ncells > 0 else {
      throw NSError(domain: "CDBReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Key not found"])
    }

    let start = (h >> 8) % ncells
    for i in 0..<ncells {
      let slotOffset = posBucket + UInt32(((start + i) % ncells) * 8)
      let h1 = readUInt32(offset: UInt64(slotOffset))
      let p1 = readUInt32(offset: UInt64(slotOffset + 4))

      if p1 == 0 {
        throw NSError(domain: "CDBReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Key not found"])
      }

      if h1 == h {
        fileHandle.seek(toFileOffset: UInt64(p1))
        let klen = readUInt32(offset: fileHandle.offsetInFile)
        let vlen = readUInt32(offset: fileHandle.offsetInFile)

        let readKey = fileHandle.readData(ofLength: Int(klen))
        let readValue = fileHandle.readData(ofLength: Int(vlen))

        if readKey == keyData {
          return readValue
        }
      }
    }

    throw NSError(domain: "CDBReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Key not found"])
  }
}

public class CDBWriter {
  private let fileHandle: FileHandle
  private let tempFilePath: String
  private let filePath: String
  private var posHeader: UInt64
  private var p: UInt64
  private var bucket: [[(UInt32, UInt64)]]

  public init(filePath: String) throws {
    self.filePath = filePath
    self.tempFilePath = Self.generateTemporaryFilePath()
    let fileManager = FileManager.default

    // Create and open the temporary file
    if !fileManager.createFile(atPath: tempFilePath, contents: nil, attributes: nil) {
      throw NSError(domain: "CDBWriterError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create temp file"])
    }

    guard let fileHandle = FileHandle(forWritingAtPath: tempFilePath) else {
      throw NSError(domain: "CDBWriterError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to open temp file for writing"])
    }

    self.fileHandle = fileHandle
    self.posHeader = 0
    self.p = UInt64((4 + 4) * 256)
    self.bucket = Array(repeating: [(UInt32, UInt64)](), count: 256)
    fileHandle.seek(toFileOffset: self.p)
  }

  public func put(key: String, value: String) throws {
    let keyData = key.data(using: .utf8)!
    let valueData = value.data(using: .utf8)!

    writeUInt32(UInt32(keyData.count), to: fileHandle)
    writeUInt32(UInt32(valueData.count), to: fileHandle)
    fileHandle.write(keyData)
    fileHandle.write(valueData)

    let h = calcHash(keyData)
    bucket[Int(h % 256)].append((h, p))

    let keyLength = UInt64(keyData.count)
    let valueLength = UInt64(valueData.count)
    let totalLength = 4 + 4 + keyLength + valueLength
    p += totalLength
  }

  public func finalize() throws {
    var posHash = p

    for b1 in bucket {
      if !b1.isEmpty {
        let ncells = b1.count * 2
        var cell = Array(repeating: (UInt32(0), UInt64(0)), count: ncells)
        for (h, p) in b1 {
          var i = Int((h >> 8) % UInt32(ncells))
          while cell[i].1 != 0 {
            i = (i + 1) % ncells
          }
          cell[i] = (h, p)
        }
        for (h, p) in cell {
          writeUInt32(h, to: fileHandle)
          writeUInt32(UInt32(p), to: fileHandle)
        }
      }
    }

    fileHandle.seek(toFileOffset: posHeader)
    for b1 in bucket {
      writeUInt32(UInt32(posHash), to: fileHandle)
      writeUInt32(UInt32(b1.count * 2), to: fileHandle)
      posHash += UInt64((b1.count * 2) * (4 + 4))
    }

    fileHandle.closeFile()

    // Perform atomic move
    let targetURL = URL(fileURLWithPath: filePath)
    let tempURL = URL(fileURLWithPath: tempFilePath)
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: targetURL.path) {
      _ = try fileManager.replaceItemAt(targetURL, withItemAt: tempURL, backupItemName: nil, options: .usingNewMetadataOnly)
    } else {
      try fileManager.moveItem(at: tempURL, to: targetURL)
    }
  }

  private func writeUInt32(_ value: UInt32, to fileHandle: FileHandle) {
    var val = value.littleEndian
    let data = Data(bytes: &val, count: 4)
    fileHandle.write(data)
  }

  private static func generateTemporaryFilePath() -> String {
    let directory = NSTemporaryDirectory()
    let fileName = UUID().uuidString + ".tmp"
    return NSURL.fileURL(withPathComponents: [directory, fileName])!.path
  }
}

