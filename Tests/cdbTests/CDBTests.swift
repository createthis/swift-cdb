import XCTest
@testable import cdb

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
  fflush(stdout)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/sh")
  process.arguments = ["-c", command]

  try process.run()
  process.waitUntilExit()

  if process.terminationStatus != 0 {
    throw NSError(domain: "CDBMakeError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "cdbmake command failed"])
  }
}

final class CDBTests: XCTestCase {

  func testRandStr() {
    let randString = randStr()
    XCTAssertTrue(randString.count >= 8 && randString.count <= 12)
  }

  func validateCDB(data: [String: String], filePath: String, referenceFilePath: String) throws {
    // Create CDB using custom implementation
    let cdbMaker = CDBMaker(data: data)
    try cdbMaker.writeCDB(to: filePath)

    // Create CDB using original cdbmake utility
    try cdbmakeTrue(filePath: referenceFilePath, data: data)

    // Check the correctness
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/cmp")
    process.arguments = [filePath, referenceFilePath]

    try process.run()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0, "Files are different")

    // Check if all values are correctly obtained
    let cdbReader = try CDBReader(filePath: filePath, posHeader: 0)

    for (key, value) in data {
      let valueFromCdb = try cdbReader.cdbget(key: key)
      XCTAssertEqual(String(data: valueFromCdb, encoding: .utf8), value, "diff: \(key)")
    }

    // Check if nonexistent keys get error
    for _ in 0..<6 {
      let key = randStr()
      if data[key] == nil {
        XCTAssertThrowsError(try cdbReader.cdbget(key: key), "found: \(key)")
      }
    }
  }

  func test_CDBMakerWriteCDB_withSmallFixedData() throws {
    let data = ["key1": "value1", "key2": "value2", "key3": "value3"]
    try validateCDB(data: data, filePath: "my.cdb", referenceFilePath: "true.cdb")
  }

  func test_CDBMakerWriteCDB_withLargerRandomData() throws {
    let n = 1000
    var data = [String: String]()
    for _ in 0..<n {
      data[randStr()] = randStr()
    }
    try validateCDB(data: data, filePath: "my.cdb", referenceFilePath: "true.cdb")
  }
}

