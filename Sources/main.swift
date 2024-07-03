import Foundation

class CDBReader {
  let fileHandle: FileHandle
  let posHeader: UInt64

  init(filePath: String, posHeader: UInt64) throws {
    self.fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
    self.posHeader = posHeader
  }

  deinit {
    fileHandle.closeFile()
  }

  func readUInt32(offset: UInt64) -> UInt32 {
    fileHandle.seek(toFileOffset: offset)
    let data = fileHandle.readData(ofLength: 4)
    return data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
  }

  func calcHash(_ key: Data) -> UInt32 {
    var hash: UInt32 = 5381
    for byte in key {
      hash = ((hash << 5) &+ hash) ^ UInt32(byte)
    }
    return hash
  }

  func cdbget(key: String) throws -> Data {
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

// Usage
do {
  let cdbReader = try CDBReader(filePath: "./test.cdb", posHeader: 0)
  let value = try cdbReader.cdbget(key: "smtp/tcp")
  print(String(data: value, encoding: .utf8)!)
} catch {
  print("Failed to read CDB file: \(error)")
}
