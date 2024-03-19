# Raspberry Pi - Build the Linux Kernel


First, clone the `raspberrypi/linux` kernel:
```
eval $(./raspberry-pi.sh env)    # Define $__kdir in your shell
echo $__kdir
git clone --depth=1 https://github.com/raspberrypi/linux $__kdir
```
This is assumed from now on.


## Build a reduced kernel

This builds a "reduced" version of the official RPi kernel. The aim is
to remove kernel modules, but at the moment they are still used. The
problem with kernel modules is that you must have them on the rootfs,
which I want to avoid.

```
./raspberry-pi.sh env         # Check where you will build
./raspberry-pi.sh kernel_build
```



## Build the official RPi kernel

This kernel builds everything you may *ever* use, and a lot of things
you will *never* use.

```
export __kcfg=$HOME/linux-rpi-official  # (or something better)
eval $(./raspberry-pi.sh env)           # Define $__kdir in your shell
cp $__kdir/arch/arm64/configs/bcm2711_defconfig $__kcfg
./raspberry-pi.sh env                   # Check build dirs
./raspberry-pi.sh kernel_build --menuconfig   # (just exit...)
```

## Build a minimal kernel

This dscribes in detail howto build a minimal kernel with support for
console printouts on an attached screen (hdmi). It can't be used for
anything, it just starts and crashes. But you can see the printouts,
so it can be used as base for a more useful kernel.  The build start
with the linux kernel [tinyconfig](https://tiny.wiki.kernel.org/).

**NOTE**: The order is important, since some options enables others!
This means that you must step down-and-up in the config menus a number
of times.

```
export __kcfg=$HOME/linux-rpi-minimal  # (or something better)
./raspberry-pi.sh env                  # Check build dirs
# (the raspberrypi/linux is assumed to be cloned to $__kdir)
./raspberry-pi.sh kernel_build --tinyconfig
# Configure:
> General setup > Configure standard kernel features 
  [*]   Enable support for printk
  [*]   BUG() support
  [*]   Load all symbols for debugging/ksymoops
> Platform selection
  [*] Broadcom SoC Support
    [*]   Broadcom BCM2835 family
    [*]   Broadcom Set-Top-Box SoCs
> Device Drivers > Mailbox Hardware Support
  [*]   BCM2835 Mailbox  
> Device Drivers > Firmware Drivers
  [*] Raspberry Pi Firmware Driver
> Device Drivers > DMA Engine support
  [*]   BCM2835 DMA engine support
  [*]   BCM2708 DMA legacy API support
> Device Drivers > Graphics support > Frame buffer Devices
  [*] Support for frame buffer device drivers
    [*]   BCM2708 framebuffer support
> Device Drivers > Graphics support
  [*] Bootup logo
> Device Drivers > Character devices
  [*] Enable TTY
> Device Drivers > Graphics support > Console display driver support
  [*] Framebuffer Console support
```


## Build a mainline kernel

It is [claimed](https://forums.raspberrypi.com/viewtopic.php?t=357536)
that mainline Linux kernels can be used. I have however failed to get
the console printouts on an attached screen to work. Only the
"rainbow-screen" is showed. It is possible that the kernel works, but
I need to see the console for trouble-shooting.

First download a kernel from [kernel.org](https://kernel.org/), then:

```
export __kver=linux-6.8
# The kernel source is unpacker in $__kdir
export __kdir=$HOME/tmp/linux/$__kver   # (or something better)
eval $(./raspberry-pi.sh env)           # Define $__kcfg in your shell
cp $PWD/config/linux-rpi-reduced $__kcfg
./raspberry-pi.sh kernel_build --menuconfig   # (just exit...)
```
