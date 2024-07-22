# Raspberry Pi - Cross-compile

Describes how to cross-compile on an Ubuntu PC to a `aarch64` target.

For the kernel build, the Ubuntu aarch64 works:
```
sudo apt install gcc-aarch64-linux-gnu
# Prefix: aarch64-linux-gnu-
```

For all user-space programs [musl-libc](https://https://musl.libc.org//)
is used instead of `libc`.

```
./raspberry-pi.sh env                # Check musldir
export musldir=/tmp/musl-cross-make  # Re-define it if you like
git clone --depth 1 https://github.com/richfelker/musl-cross-make.git $musldir
cd $musldir
make -j$(nproc) TARGET=aarch64-linux-musl
make -j$(nproc) TARGET=aarch64-linux-musl install OUTPUT=$PWD/aarch64
# To build user-space programs with musl:
export PATH=$musldir/aarch64/bin:$PATH
# Prefix: aarch64-linux-musl-
```

The advantage of `musl-libc` is for instance that it's small, but more
important (IMO), that you can use static linking without breaking any
license (like LGPL for libc)
