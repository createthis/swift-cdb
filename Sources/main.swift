import Foundation

func calcHash(_ key: Data) -> UInt32 {
  var hash: UInt32 = 5381
  for byte in key {
    hash = ((hash << 5) &+ hash) ^ UInt32(byte)
  }
  return hash
}

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

class CDBMaker {
    let fileHandle: FileHandle
    let data: [String: String]

    init(filePath: String, data: [String: String]) throws {
      let fileManager = FileManager.default
      if !fileManager.fileExists(atPath: filePath) {
        fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
      }
      self.fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
      self.data = data
    }

    deinit {
        fileHandle.closeFile()
    }

    func writeUInt32(_ value: UInt32) {
        var val = value.littleEndian
        let data = Data(bytes: &val, count: 4)
        fileHandle.write(data)
    }

    func writeData(_ data: Data) {
        fileHandle.write(data)
    }

    func writeCDB() {
        let posHeader = fileHandle.offsetInFile

        // Skip header
        var p = posHeader + UInt64((4 + 4) * 256)
        fileHandle.seek(toFileOffset: p)

        var bucket = Array(repeating: [(UInt32, UInt64)](), count: 256)

        // Write data & make hash
        for (k, v) in data {
            let keyData = k.data(using: .utf8)!
            let valueData = v.data(using: .utf8)!

            writeUInt32(UInt32(keyData.count))
            writeUInt32(UInt32(valueData.count))
            writeData(keyData)
            writeData(valueData)

            let h = calcHash(keyData)
            bucket[Int(h % 256)].append((h, p))

            let keyLength = UInt64(keyData.count)
            let valueLength = UInt64(valueData.count)
            let totalLength = 4 + 4 + keyLength + valueLength
            p += totalLength
        }

        var posHash = p

        // Write hashes
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
                    writeUInt32(h)
                    writeUInt32(UInt32(p))
                }
            }
        }

        // Write header
        fileHandle.seek(toFileOffset: posHeader)
        for b1 in bucket {
            writeUInt32(UInt32(posHash))
            writeUInt32(UInt32(b1.count * 2))
            posHash += UInt64((b1.count * 2) * (4 + 4))
        }
    }

    func createCDB() {
        writeCDB()
    }
}

func randStr() -> String {
    let length = Int.random(in: 8...12)
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<length).map{ _ in letters.randomElement()! })
}

func cdbmakeTrue(filePath: String, data: [String: String]) throws {
    let inputFileName = "input.txt"
    let tempFileName = "\(filePath).tmp"
    let inputFile = URL(fileURLWithPath: inputFileName)
    let fileHandle: FileHandle
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: inputFile.path) {
        try fileManager.removeItem(atPath: inputFile.path)
    }
    fileManager.createFile(atPath: inputFile.path, contents: nil, attributes: nil)
    fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: inputFile.path))

    // Write key-value pairs to the temporary file in the cdbmake format
    for (key, value) in data {
        let keyData = key.data(using: .utf8)!
        let valueData = value.data(using: .utf8)!
        let line = "+\(keyData.count),\(valueData.count):\(key)->\(value)\n"
        fileHandle.write(line.data(using: .utf8)!)
    }
    fileHandle.write("\n".data(using: .utf8)!)  // Signal end of input
    fileHandle.closeFile()

    // Use a subshell to call DJB's original `cdbmake`
    let command = "cdbmake \"\(filePath)\" \"\(tempFileName)\" < \"\(inputFileName)\""
    print("Running command: \(command)")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw NSError(domain: "CDBMakeError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "cdbmake command failed"])
    }
}

func test(n: Int) throws {
    var data = [String: String]()

    for _ in 0..<n {
        data[randStr()] = randStr()
    }

    // Create CDB files
    let cdbMaker = try CDBMaker(filePath: "my.cdb", data: data)
    cdbMaker.writeCDB()
    try cdbmakeTrue(filePath: "true.cdb", data: data)

    // Check the correctness
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/cmp")
    process.arguments = ["my.cdb", "true.cdb"]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        print("Files are different")
    } else {
        print("Files are identical")
    }

    // Check if all values are correctly obtained
    let cdbReader = try CDBReader(filePath: "my.cdb", posHeader: 0)

    for (key, value) in data {
        let valueFromCdb = try cdbReader.cdbget(key: key)
        assert(String(data: valueFromCdb, encoding: .utf8) == value, "diff: \(key)")
    }

    // Check if nonexistent keys get error
    for _ in 0..<(n * 2) {
        let key = randStr()
        if data[key] == nil {
            do {
                _ = try cdbReader.cdbget(key: key)
                assert(false, "found: \(key)")
            } catch {
                // Expected error
            }
        }
    }
}


// Usage
do {
  //let cdbReader = try CDBReader(filePath: "./test.cdb", posHeader: 0)
  //let value = try cdbReader.cdbget(key: "smtp/tcp")
  //print(String(data: value, encoding: .utf8)!)
  try test(n: 1000)
} catch {
  //print("Failed to read CDB file: \(error)")
  print("Test failed: \(error)")
}
