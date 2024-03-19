# Raspberry Pi - Cross-compile

Describes how to cross-compile on an Ubuntu PC to a `aarch64` target.


```
sudo apt install gcc-aarch64-linux-gnu
# Prefix: aarch64-linux-gnu-
```


To use [musl-libc](https://https://musl.libc.org//) instead of `libc`
(as [Alpine Linux](https://www.alpinelinux.org/)):
```
musldir=$GOPATH/src/github.com/richfelker/musl-cross-make
git clone --depth 1 https://github.com/richfelker/musl-cross-make.git $musldir
cd $musldir
make
make install  # To ./output by default
# To build user-space programs with musl:
export PATH=$musldir/output/bin:$PATH
# Prefix: aarch64-linux-musl-
```

The advantage of `musl-libc` is for instance that it's small, but more
important (IMO), that you can use static linking without breaking any
license (like LGPL for libc)
