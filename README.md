bcmstat
=======

Simple Raspberry Pi command line monitoring tool:

* CPU fequencies (ARM, Core, h264)
* Temperature (current and peak)
* IRQ/s
* Network Rx/Tx
* GPU mem usage
* CPU load
* RAM usage (with/without swap)

Tested with Raspbian, OpenELEC and Raspbmc.

Displayed values can be coloured (white, green, amber and red) to highlight excess usage or resource depletion.

View available options with -h.

Specify a default configuration in ~/.bcmstat.conf, eg:
```
xgcd10
```

####Example output:
```
rpi512:~ # ./bcmstat.sh cxgd10
Governor: ondemand
  Memory: 512MB (256MB ARM, 256MB GPU)
Min Freq: 1000Mhz |  250Mhz |  600Mhz
Max Freq: 1000Mhz |  500Mhz |  600Mhz
Voltages:      +4, 1.30V    | +4, 1.30V
   Other: TEMP_LIMIT=85C, FORCE_TURBO
 Version: Jan 10 2014 16:54:51, version efa116b5c8859c352322cb27e13baccbea583ef7 (clean) (release)
vcg path: /usr/bin/vcgencmd
  Codecs: H264 WVC1 MPG2 VP8 VORBIS MJPG
  Booted: Tue Jan 21 03:50:40 2014
Priority: Lowest (+19)

Time          ARM     Core     h264  Core Temp (Max)   IRQ/s      RX B/s      TX B/s  GPUMem Free   %user   %nice %system   %idle %iowait    %irq  %s/irq  %total  Memory Free/Used
========  =======  =======  =======  ===============  ======  ==========  ==========  ===========  ======  ======  ======  ======  ======  ======  ======  ======  ================
08:11:58  1000Mhz   500Mhz     0Mhz  58.00C (58.00C)   1,118       1,088       8,351   197M (83%)   13.33   26.67   60.00    0.00    0.00    0.00    0.00  100.00  281,480 kB/26.5%
08:12:08  1000Mhz   500Mhz     0Mhz  58.00C (58.00C)   1,003          90         119   197M (83%)   13.55    1.47    4.13   79.26    0.00    0.00    0.00   20.74  281,480 kB/26.5%
08:12:19  1000Mhz   500Mhz     0Mhz  58.00C (58.00C)   1,004         138         110   197M (83%)   13.76    1.47    3.93   79.59    0.00    0.00    0.00   20.41  281,480 kB/26.5%
08:12:29  1000Mhz   500Mhz     0Mhz  57.00C (58.00C)   1,004         124         114   197M (83%)   13.76    1.28    4.42   79.71    0.00    0.00    0.00   20.29  281,480 kB/26.5%
08:12:39  1000Mhz   500Mhz     0Mhz  58.00C (58.00C)   1,003          89          98   197M (83%)   13.56    1.08    4.42   79.58    0.00    0.00    0.00   20.42  281,480 kB/26.5%
08:12:49  1000Mhz   500Mhz     0Mhz  58.00C (58.00C)   1,004         119         116   197M (83%)   12.67    1.37    4.12   79.64    0.00    0.00    0.00   20.36  281,480 kB/26.5%
08:12:59  1000Mhz   500Mhz     0Mhz  58.00C (58.00C)   1,006         112         232   232M (98%)   12.51    1.28    4.73   79.60    0.10    0.00    0.00   20.40  342,560 kB/10.6%
08:13:23  1000Mhz   500Mhz     0Mhz  61.00C (61.00C)   1,111      13,770       4,586   232K (98%)   78.51    2.10   14.53    1.37    0.77    0.00    2.64   98.63  291,656 kB/23.8%
08:13:34   999Mhz   499Mhz     0Mhz  62.00C (62.00C)   1,917     744,544      23,932   198M (83%)   76.78    1.50    8.47    5.30    1.35    0.00    4.43   94.70  291,492 kB/23.9%
08:13:44  1000Mhz   500Mhz     0Mhz  60.00C (62.00C)   1,129       9,927       6,041   198M (83%)   24.81    1.36    5.45   60.12    6.62    0.00    0.10   39.88  291,516 kB/23.9%
08:13:54  1000Mhz   500Mhz     0Mhz  59.00C (62.00C)   1,003          98         127   198M (83%)   13.64    1.57    4.42   65.57   13.45    0.00    0.00   34.43  291,484 kB/23.9%
08:14:05  1000Mhz   500Mhz     0Mhz  59.00C (62.00C)   1,003          96         111   198M (83%)   18.43    1.66    4.70   59.61   14.28    0.00    0.00   40.39  291,528 kB/23.9%
08:14:15   999Mhz   500Mhz     0Mhz  60.00C (62.00C)   1,002          68          98   198M (83%)   15.55    1.17    5.15   63.44   13.02    0.00    0.00   36.56  291,488 kB/23.9%
08:14:26  1000Mhz   500Mhz     0Mhz  59.00C (62.00C)   1,004         161         111   198M (83%)   13.54    1.28    4.71   71.14    7.46    0.00    0.00   28.86  291,520 kB/23.9%
08:14:36  1000Mhz   500Mhz     0Mhz  59.00C (62.00C)   1,003          88          99   198M (83%)   14.42    1.28    4.81   78.70    0.00    0.00    0.00   21.30  291,520 kB/23.9%
08:14:46  1000Mhz   500Mhz     0Mhz  59.00C (62.00C)   1,003         111         114   198M (83%)   12.26    1.57    4.61   78.68    0.00    0.00    0.10   21.32  291,528 kB/23.9%
```
