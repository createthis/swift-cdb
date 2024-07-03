# What
I took the code at https://www.unixuser.org/~euske/doc/cdbinternals/pycdb.py.html and made it
[Python 3 compatible](https://github.com/createthis/euske_pycdb), then I converted it to Swift.

# I still don't get it. What is CDB?

Some links for you:

1. https://cr.yp.to/cdb/cdb.txt and https://cr.yp.to/cdb.html
2. http://www.cse.yorku.ca/~oz/hash.html
3. https://www.unixuser.org/~euske/doc/cdbinternals/index.html

# Getting Started
Install the C version of `cdb`:

```bash
brew install cdb
```

The unit tests need `cdbmake` from this library.

Also, use it to make a `test.cdb` file from `/etc/services`:
```bash
cdbmake-sv test.cdb test.tmp < /etc/services
```

Query this cdb using the C version of `cdbget:
```bash
# result should be 25
cdbget smtp/tcp < test.cdb && echo ''
```

Finally, try the swift version:
```bash
swift run
```
