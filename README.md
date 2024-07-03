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

Query it using this Swift library:
```swift
import cdb

let cdbReader = try CDBReader(filePath: "test.cdb", posHeader: 0)
let valueFromCdb = try cdbReader.cdbget(key: "smtp/tcp")
print("valueFromCdb=\(valueFromCdb)")
```

## Automated compatibility testing
The Swift unit tests need `cdbmake` from the original C library, so install that first (see above).

Finally, you can test that the output of this Swift library matches the output of the original C version:
```bash
swift test
```
