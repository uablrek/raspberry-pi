# Raspberry Pi - Network boot

This network boot instruction is generic, see also the [RPi documentation](
https://www.raspberrypi.com/documentation/computers/remote-access.html#raspberry-pi-4-model-b).
When developing and testing kernels and initrds netboot is convenient,
almost a necessity actually.

How it works:

1. The firmware on the RPi tries to get an address and the tftp via
   [DHCP](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol)
2. The RPi downloads the start images (e.g. start4.elf), and config files
   (config.txt, cmdline.txt) via
   [TFTP](https://en.wikipedia.org/wiki/Trivial_File_Transfer_Protocol)
3. The RPi downloads the kernel and initrd via TFTP, and starts linux

The `initrd` has limited size (and tftp is very slow), so a new
`tmpfs` root is created by the `initrd` and is populated with ovls via
`http`. So we must start a http server, and collect some ovls. At
least a "rootfs" is *required*.

Quick start if you feel lucky:
```
./raspberry-pi.sh versions                 # Check Downloads
vi config/udhcpd.conf                      # Alter the interface
./raspberry-pi.sh setup --dev=<your-UNUSED-wired-interface>
```

## Enable network boot

First boot the RPi from an SD card and change boot order. Also get the
serial-no which will be used for tftp boot later.

```
ssh pi@raspberrypi  # passwd "raspberry"
# Get the serial-no. This is the $__id needed for tftp boot
grep Serial /proc/cpuinfo | cut -d ' ' -f 2 | cut -c 9-16
sudo raspi-config
# Advanced Options > Boot Order > B3 ...
# Reboot
# Power-off, and remove the SD-card
```


## Connect your PC to the RPi with wired ethernet

You want to be in control over the boot network, for instance start a
DHCP server without conflicting with your ISP router. I use a direct
ethernet cable between my PC and the RPi. Since I use wifi for
internet there is no conflict. How you configure the wired network
will surely differ, but here is how I do:

```
dev=enp5s0            # Wired interface connected to the rpi
addr=192.168.40.1/24  # Address of the wired interface
cidr=192.168.40.0/24
sudo ip link set up dev $dev
sudo ip addr add $addr dev $dev
sudo iptables -t nat -A POSTROUTING -s $cidr -j MASQUERADE
sudo iptables -A FORWARD -s $cidr -j ACCEPT
sudo iptables -A FORWARD -d $cidr -j ACCEPT
# Or
./raspberry-pi.sh interface_setup --dev=enp5s0 --local-addr=192.168.40.1/24
```

Masquerading is used for internet access from the RPi.


## TFTP server

The Ubuntu [tftpd package](
https://askubuntu.com/questions/201505/how-do-i-install-and-run-a-tftp-server)
seem to have bugs and the `atftp` package doesn't work either, so the best
way seem to be to build atftp locally:

```
./raspberry-pi.sh versions       # Check that atftp archive is downloaded
./raspberry-pi.sh atftp_build
```

Then start with:

```
export __id=(your-serial-number)
./raspberry-pi.sh tftpd
sudo tail -f /var/log/syslog
```

## DHCP server

Be careful with the DHCP server, you don't want it to conflict with
your internet setup. I am using `udhcpd` which is included in `BusyBox`.

```
vi ./config/udhcpd.conf  # Especially the "interface"
./raspberry-pi.sh dhcpd
```

## Firmware files

Some firmware boot files must be downloaded (to $HOME/Downloads or $ARCHIVE):

* [bcm2711-rpi-4-b.dtb](https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/bcm2711-rpi-4-b.dtb)
* [fixup4.dat](https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/fixup4.dat)
* [start4.elf](https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/start4.elf)

These are the most essential, but there may be others.


## Boot!

If you have built the local kernel and initrd, you should be able to do:

```
#export __id=(your-serial-number) # if needed
./raspberry-pi.sh tftp_setup
eval $(./raspberry-pi.sh env)     # Define $__tftproot and $__id
ls -lh $__tftproot/$__id
# Power on your RPi, and pray...
```

#### Trouble-shooting

Well, that didn't work...

The most likely is a load problem. Both the tftp and dhcp servers log
to the syslog, so do:

```
sudo tail -f  /var/log/syslog
```

Reboot the RPi and monitor the printouts. Check especially if you have
the `$__id` correct.  If the files and IP-addresses seem to be loaded,
and it still doesn't work (e.g. rainbow-screen), try another
distribution such as Alpine below.



## Alpine Linux

[Alpine Linux](https://www.alpinelinux.org/) has a [netboot instruction](
https://wiki.alpinelinux.org/wiki/Raspberry_Pi#Netboot). Copy the boot
files to a directory. You may omit the firmware files if you have downloaded
them before.

At the time of writing, the kernel and initrd links were broken. But
just skip the tailing `4`, like vmlinuz-rpi4 -> vmlinuz-rpi. And
modify `config.txt` accordingly.


```
alpine_dir=/your/alpine/boot/files/directory
ls -lh $alpine_dir
-rw-rw-r-- 1 uablrek uablrek  177 Mar 16 09:35 cmdline.txt
-rw-rw-r-- 1 uablrek uablrek   61 Mar 19 15:07 config.txt
-rw-rw-r-- 1 uablrek uablrek 4.7M Mar 15 10:26 initramfs-rpi
-rw-rw-r-- 1 uablrek uablrek  23M Mar 15 10:26 vmlinuz-rpi
cat $alpine_dir/config.txt
[pi4]
kernel=vmlinuz-rpi
initramfs initramfs-rpi
arm_64bit=1

./raspberry-pi.sh tftp_setup $alpine_dir
ls -lh $__tftproot/$__id
# Power-on the RPi
```

