# What
I took the code at https://www.unixuser.org/~euske/doc/cdbinternals/pycdb.py.html and made it
[Python 3 compatible](https://github.com/createthis/euske_pycdb), then I converted it to Swift.

# I still don't get it. What is CDB?

Some links for you:

1. https://cr.yp.to/cdb/cdb.txt and https://cr.yp.to/cdb.html
2. http://www.cse.yorku.ca/~oz/hash.html
3. https://www.unixuser.org/~euske/doc/cdbinternals/index.html

# Getting started

## Installing and using C library
The original C version of `cdb` (written by DJB) is only necessary if you want to prove to 
yourself that this Swift library is compatible:

```bash
brew install cdb
```

The Swift unit tests need `cdbmake` from this library.

## Manual compatibility testing
Use the C library to make a `test.cdb` file from `/etc/services`:
```bash
cdbmake-sv test.cdb test.tmp < /etc/services
```

Query this cdb using the C version of `cdbget:
```bash
# result should be 25
cdbget smtp/tcp < test.cdb && echo ''
```

See `Usage` below for how to perform the same `cdbget` in swift.

## Usage

### Naming
Swift's package system doesn't appear to have a good way to deal with namespace conflicts, so the classes are manually
prefixed with `CDB`. Example: `CDBReader`. `get` is also a reserved keyword, so we have to live with triply redundant 
`cdbget()`.

### CDBReader
Query it using this Swift library:
```swift
import cdb

let cdbReader = try CDBReader(filePath: "test.cdb", posHeader: 0)
let valueFromCdb = try cdbReader.cdbget(key: "smtp/tcp")
print("valueFromCdb=\(valueFromCdb)")
```

### CDBWriter
Alternatively, to create a cdb using swift, do something like this:

```swift
import cdb

let data = ["key1": "value1", "key2": "value2", "key3": "value3"]
let cdbWriter = try CDBWriter(filePath: "my.cdb")
for (key, value) in data {
  try cdbWriter.put(key: key, value: value)
}
try cdbWriter.finalize();
```

## Automated compatibility testing
The Swift unit tests need `cdbmake` from the original C library, so install that first (see above).

Finally, you can test that the output of this Swift library matches the output of the original C version:
```bash
swift test
```
