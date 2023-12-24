bcmstat
=======

Simple Raspberry Pi command line monitoring tool:

* CPU fequencies (ARM, Core, H264, V3D, ISP)
* Temperature (current and peak) for Core and/or PMIC
* IRQ/s
* Network Rx/Tx
* System utilisation (percentage user, nice, idle etc.)
* CPU load (including individual cores when available)
* GPU mem usage
* RAM usage (with/without swap)
* Memory leak detection (`D`/`A` options - instantaneous and accumulated memory deltas)
* Undervoltage, ARM frequency cap and temperature throttle event monitoring
* Customisable columns

Tested with Raspbian, LibreELEC and OSMC/Raspbmc.

Displayed values can be coloured (white, green, amber and red) to highlight excess usage or resource depletion. Disable with `m` option.

View available options with `-h`.

Specify a default configuration in ~/.bcmstat.conf, eg:
```
xgd10
```

### Installing on the Pi

To install the latest version directly from this github repository:
```
curl -Ls https://raw.githubusercontent.com/MilhouseVH/bcmstat/master/bcmstat.sh -o ~/bcmstat.sh
chmod +x ~/bcmstat.sh
```

### Example output
```
rpi2:~ # ./bcmstat.sh xgpd10
  Config: v0.3.7, args "Cxgpd10", priority lowest (+19)
   Board: 4 x ARMv7 cores available, ondemand governor (Pi3 rev 1.2, BCM2837 SoC with 1GB RAM by Sony)
  Memory: 1008MB (split 688MB ARM, 320MB GPU)
HW Block: |   ARM   |  Core  |  H264  |    SDRAM    |
Min Freq: | 1200MHz | 500MHz |   0MHz |    500MHz   |
Max Freq: | 1200MHz | 500MHz | 400MHz |    500MHz   |
Voltages: |         0, 1.3750V        | +2, 1.2500V |
   Other: temp_limit=85, force_turbo=1
Firmware: Feb 25 2016 18:56:38, version dea971b793dd6cf89133ede5a8362eb77e4f4ade (clean) (release)
  Codecs: H264 WVC1 MPG2 VP8 VORBIS MJPG
  Booted: Thu Feb 25 22:14:50 2016

Time         ARM    Core    H264 Core Temp (Max)  IRQ/s     RX B/s     TX B/s  %user  %nice   %sys  %idle  %iowt   %irq %s/irq %total   cpu0   cpu1   cpu2   cpu3 GPUMem Free Memory Free/Used
======== ======= ======= ======= =============== ====== ========== ========== ====== ====== ====== ====== ====== ====== ====== ====== ====== ====== ====== ====== =========== ================
10:58:29 1000Mhz  499Mhz    0Mhz 49.77C (49.77C)    730        451      6,159  12.63  10.10  17.68  55.55   0.00   0.00   0.00  44.45  29.30  39.40  59.60  39.40 242M ( 80%) 588,264 kB/14.8%
10:58:39 1000Mhz  500Mhz    0Mhz 47.08C (49.77C)    693      1,099        596   4.49   0.62   1.70  92.80   0.00   0.00   0.00   7.20   5.20   2.44   5.99  15.27 242M ( 80%) 588,484 kB/14.8%
10:58:49 1000Mhz  500Mhz    0Mhz 48.15C (49.77C)    692        166        614   5.04   0.72   1.43  92.40   0.00   0.00   0.00   7.60  20.54   2.06   4.53   3.35 242M ( 80%) 588,236 kB/14.8%
10:59:00 1000Mhz  500Mhz    0Mhz 48.69C (49.77C)    695        796        611   4.98   0.59   1.63  92.27   0.00   0.00   0.02   7.73  17.58   8.00   1.98   3.26 242M ( 80%) 588,544 kB/14.8%
10:59:10 1000Mhz  500Mhz    0Mhz 46.54C (49.77C)    701      1,057        987   4.46   0.72   1.34  92.97   0.00   0.00   0.00   7.03   3.88   2.79   2.40  19.04 242M ( 80%) 588,644 kB/14.8%
10:59:20  999Mhz  500Mhz    0Mhz 47.62C (49.77C)    697      1,402        639   4.52   0.57   1.36  93.03   0.00   0.00   0.02   6.97  18.73   2.82   3.01   3.31 242M ( 80%) 588,176 kB/14.8%
10:59:30  999Mhz  499Mhz    0Mhz 46.54C (49.77C)    695        496        784   4.45   0.62   1.48  92.94   0.02   0.00   0.00   7.06   6.41   2.75  16.31   2.85 242M ( 80%) 588,408 kB/14.8%
10:59:40 1000Mhz  500Mhz    0Mhz 48.15C (49.77C)    692        153        555   4.81   0.79   1.59  92.44   0.00   0.00   0.00   7.56   3.30   2.71  20.94   3.20 242M ( 80%) 588,368 kB/14.8%
10:59:50 1000Mhz  500Mhz    0Mhz 48.69C (49.77C)    691        153        537   4.85   0.64   1.51  92.38   0.00   0.00   0.02   7.62   3.54   6.41  18.09   2.46 242M ( 80%) 588,700 kB/14.8%
11:00:00 1000Mhz  500Mhz    0Mhz 47.62C (49.77C)    696        847        759   4.89   0.69   1.53  92.43   0.00   0.00   0.00   7.57   4.51  20.82   3.12   1.94 242M ( 80%) 588,180 kB/14.8%
11:00:10 1000Mhz  500Mhz    0Mhz 48.69C (49.77C)    706      2,290      1,073   4.82   0.69   1.76  92.17   0.00   0.00   0.00   7.83  11.84  13.91   2.14   3.33 242M ( 80%) 588,328 kB/14.8%
11:00:20 1000Mhz  500Mhz    0Mhz 46.54C (49.77C)    692        191        505   4.15   0.62   1.39  93.30   0.00   0.00   0.00   6.70   7.62  10.40   1.66   7.02 242M ( 80%) 588,324 kB/14.8%
11:00:30  999Mhz  500Mhz    0Mhz 48.69C (49.77C)    694        456        774   4.77   0.74   1.69  92.20   0.00   0.00   0.02   7.80   9.24   1.79   3.08  17.18 242M ( 80%) 588,504 kB/14.8%
```

### With "leak detection" showing potential GPU and ARM memory leak

Notice how negative allocations exceed the positive frees.
```
rpi2:~ # ./bcmstat.sh Dd10
  Config: v0.3.4, args "Dd10", priority lowest (+19)
     CPU: 4 x ARMv7 cores available, using ondemand governor
  Memory: 1008MB (split 688MB ARM, 320MB GPU)
HW Block: |   ARM   |  Core  |  H264  |    SDRAM    |
Min Freq: | 1000MHz | 500MHz |   0MHz |    450MHz   |
Max Freq: | 1000MHz | 500MHz | 400MHz |    450MHz   |
Voltages: |        +4, 1.3940V        | +1, 1.2250V |
   Other: temp_limit=85, force_turbo=1, avoid_pwm_pll=1
Firmware: Sep 9 2015 23:05:32, version de72f07669414925f3fde745fb860bc5d4d193d8 (clean) (release)
  Codecs: H264 WVC1 MPG2 VP8 VORBIS MJPG
  Booted: Sun Sep 13 23:23:22 2015

Time         ARM    Core    H264 Core Temp (Max)  IRQ/s     RX B/s     TX B/s GPUMem Free Memory Free/Used Delta GPU B      Mem kB
======== ======= ======= ======= =============== ====== ========== ========== =========== ================ =======================
11:01:18 1000Mhz  499Mhz    0Mhz 50.31C (50.31C)    718      2,482      6,492 242M ( 80%) 588,232 kB/14.8%           0        +452
11:01:28 1000Mhz  500Mhz    0Mhz 48.15C (50.31C)    696        946      1,218 242M ( 80%) 588,552 kB/14.8%           0        +320
11:01:38 1000Mhz  500Mhz  399Mhz 48.69C (50.31C)  1,042    351,271     19,671 232M ( 77%) 583,164 kB/15.6% -10,485,760      -5,388
11:01:48 1000Mhz  500Mhz  400Mhz 47.08C (50.31C)  1,199    547,135     66,577 244M ( 81%) 580,920 kB/15.9% +12,582,912      -2,244
11:01:58 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)    907    153,829     65,130 244M ( 81%) 581,100 kB/15.9%           0        +180
11:02:08 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)    924    198,512     65,096 244M ( 81%) 580,908 kB/15.9%           0        -192
11:02:18  999Mhz  500Mhz  400Mhz 46.54C (50.31C)    924    188,646     65,642 242M ( 80%) 580,456 kB/16.0%  -2,097,152        -452
11:02:28 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)    928    187,799     65,830 241M ( 80%) 579,884 kB/16.0%  -1,048,576        -572
11:02:39 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)    864    113,863     63,104 240M ( 80%) 579,264 kB/16.1%  -1,048,576        -620
11:02:49 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)    889    127,125     64,787 240M ( 80%) 579,348 kB/16.1%           0         +84
11:02:59 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)    913    176,765     65,821 238M ( 79%) 577,240 kB/16.4%  -2,097,152      -2,108
11:03:09 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)  1,135    475,837     72,189 236M ( 78%) 575,200 kB/16.7%  -2,097,152      -2,040
11:03:19 1000Mhz  500Mhz  400Mhz 46.00C (50.31C)  1,069    393,120     71,683 236M ( 78%) 574,024 kB/16.9%           0      -1,176
11:03:29 1000Mhz  500Mhz  400Mhz 46.54C (50.31C)  1,085    401,239     71,326 236M ( 78%) 573,588 kB/17.0%           0        -436
11:03:39 1000Mhz  499Mhz  400Mhz 46.54C (50.31C)  1,189    531,435     74,723 235M ( 78%) 573,008 kB/17.0%  -1,048,576        -580
11:03:49 1000Mhz  499Mhz  400Mhz 46.54C (50.31C)  1,050    353,963     71,205 235M ( 78%) 573,296 kB/17.0%           0        +288
11:03:59 1000Mhz  500Mhz    0Mhz 47.62C (50.31C)    822     63,846     25,207 227M ( 75%) 576,172 kB/16.6%  -8,388,608      +2,876
11:04:09 1000Mhz  500Mhz    0Mhz 47.08C (50.31C)    692        199        641 227M ( 75%) 576,216 kB/16.6%           0         +44
11:04:19 1000Mhz  500Mhz    0Mhz 47.62C (50.31C)    695        624        672 227M ( 75%) 576,484 kB/16.5%           0        +268
11:04:30 1000Mhz  500Mhz    0Mhz 47.08C (50.31C)    697      1,348        786 227M ( 75%) 575,952 kB/16.6%           0        -532
11:04:40 1000Mhz  500Mhz    0Mhz 47.08C (50.31C)    701      1,331        879 227M ( 75%) 576,600 kB/16.5%           0        +648
```
