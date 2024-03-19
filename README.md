# Raspberry Pi

Experiments with my [Raspberry Pi 4 Model B](
https://www.raspberrypi.com/products/raspberry-pi-4-model-b/specifications/)
with a [3.5" TFT display](
http://www.lcdwiki.com/MHS-3.5inch_RPi_Display).

The original goal was to build a [PipBoy](
https://www.instructables.com/Pipboy-Built-From-Scrap/) for my boy.  I
may still end up there, but now the focus is on learning, and to build
a small system with my own kernel and rootfs (no distro).  Since
experimenting with kernel builds includes re-build and re-load perhaps
50 times in a day, building on RPi, or using a SD-card is not feasible.
Instead [cross-compilation](cross-compile.md) and [network
booting](network-boot.md) is used. The basic installation is described
in the [RPi documentation](
https://www.raspberrypi.com/documentation/computers/) and is not
repeated here.

Recommended use:

1. Clone this repo, and setup the environment as described below
2. [Cross compile](cross-compile.md) - Build on your Linux PC rather than on the RPi simplifies and saves a lot of time
3. [Kernel build](kernel.md) - Build a small kernel
4. [Initrd](initrd.md) - Build an initrd with a custom rootfs
6. [Network boot](network-boot.md) - Removes the need of an SD-card. Your PC is used as a dhcp+tftp server



## The `raspberry-pi.sh` script and environment setup

The `raspberry-pi.sh` script is used for most tasks.

```
./raspberry-pi.sh             # Invoke without parameters for a help printout
./raspberry-pi.sh env         # Shows the environment that will be used
eval $(./raspberry-pi.sh env) # Define the variables in your shell
```

The `$RASPBERRYPI_WORKSPACE` variable points to a directory where all
stuff is stored by default. Files that are supposed to be downloaded
are searched for in `$HOME/Downloads/` and `$ARCHIVE`.

Options to `raspberry-pi.sh` can be specified on the command line,
like `--kver=linux-6.8` or as an environment variable like
`export __kver=linux-6.8`.

Example:
```
export RASPBERRYPI_WORKSPACE=$HOME/tmp/raspberrypi  # (or something better)
#export ARCHIVE=$HOME/archive       # (optional)
# For network boot:
export __id=...                     # The serial number of your rpi4
export __local_addr='192.168.40.1'  # Local address of your tftp server
```

The "id" can be found on your RPi with:
```
grep Serial /proc/cpuinfo | cut -d ' ' -f 2 | cut -c 9-16
```
