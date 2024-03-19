# Raspberry-Pi - Initrd

Build an initial ramdisk, `initrd`. An "initrd" in this context is
actually a (compressed) `cpio` file. It is unpacked by the kernel and
is used as rootfs. The intention is to do necessary initialisations,
and then do a `switch_root` to the real rootfs, but you may stay with
the `initrd` as rootfs if you like.

The rootfs uses [BusyBox](https://www.busybox.net/), so it must be
downloaded:

```
eval $(./raspberry-pi.sh env)   # Define $__bbver
curl -L https://busybox.net/downloads/$__bbver.tar.bz2 > $HOME/Downloads/$__bbver.tar.bz2
```

The build uses `musl`, so [cross compile for user space](cross-compile.md)
must be installed. Then build with:

```
./raspberry-pi.sh busybox_build
```

The `initrd` is created using kernel tools, and is stored (by default)
in the `$__kobj` directory, so usually the kernel must have been
built before this.

```
./raspberry-pi.sh build_initrd
eval $(./raspberry-pi.sh env)   # Define $__initrd
zcat $__initrd | cpio -i --list # Check the contents
```

This builds a truly minimal rootfs. Basically the `busybox` binary
(statically linked), and an `/init` script. It will drop out to
a shell.

For a somewhat more useful rootfs do:
```
./raspberry-pi.sh build_initrd ovl/rootfs0
```

This rootfs adds networking and setup a telnet server (no passwd).  It
also introduces the "ovl" concept (borrowed from [xcluster](
https://github.com/Nordix/xcluster/blob/master/doc/overlays.md)) which
is a directory with a "tar" script that should emit a tar-file.

```
cd ovl/rootfs0
./tar - | tar t
```

This is the prefered way to extend the rootfs.


## Embedded initrd

The rootfs can be included in the kernel image. In the config:

```
./raspberry-pi.sh kernel_build --menuconfig
> General setup
   [*] Initial RAM filesystem and RAM disk
   (initrd.cpio.gz) Initramfs source file(s)
```

Now you can omit the `initramfs` in the `config.txt` file.
