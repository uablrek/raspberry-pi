# Raspberry Pi - Cross-compile

Describes how to cross-compile on an Ubuntu PC to a `aarch64` target.


```
sudo apt install gcc-aarch64-linux-gnu
# Prefix: aarch64-linux-gnu-
```

To use [musl-libc](https://https://musl.libc.org//) instead of `libc`
(as [Alpine Linux](https://www.alpinelinux.org/)):
```
eval $(./raspberry-pi.sh env)           # Define $RASPBERRYPI_WORKSPACE
musldir=$RASPBERRYPI_WORKSPACE/musl-cross-make # (or something better)
git clone --depth 1 https://github.com/richfelker/musl-cross-make.git $musldir
cd $musldir
make -j$(nproc) TARGET=aarch64-linux-musl   # (this takes ages!)
make -j$(nproc) TARGET=aarch64-linux-musl install  # To ./output by default
# To build user-space programs with musl:
export PATH=$musldir/output/bin:$PATH
# Prefix: aarch64-linux-musl-
```

The advantage of `musl-libc` is for instance that it's small, but more
important (IMO), that you can use static linking without breaking any
license (like LGPL for libc)
