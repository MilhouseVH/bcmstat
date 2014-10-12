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

####Installing on the Pi:

To install the latest version directly from this github repository:
```
curl -Ls https://raw.githubusercontent.com/MilhouseVH/bcmstat/master/bcmstat.sh -o ~/bcmstat.sh
chmod +x ~/bcmstat.sh
```

####Example output:
```
rpi512:~ # ./bcmstat.sh cxgd10
  Config: v0.1.6, args "cxgd10", priority lowest (+19)
Governor: ondemand
  Memory: 512MB (split 256MB ARM, 256MB GPU) plus 128MB Swap
HW Block: |   ARM   |  Core  |  H264  |   SDRAM   |
Min Freq: | 1000Mhz | 500Mhz |   0Mhz |   600Mhz  |
Max Freq: | 1000Mhz | 500Mhz | 250Mhz |   600Mhz  |
Voltages: |         +4, 1.30V         | +4, 1.30V |
   Other: temp_limit=85, force_turbo=1, hdmi_force_hotplug=1
Firmware: Jun 18 2014 18:43:44, version 1a6f79b82240693dcdb9347b33ab16f656b5f067 (clean) (release)
  Codecs: H264 WVC1 MPG2 VP8 VORBIS MJPG
  Booted: Thu Jun 19 04:56:18 2014

Time          ARM     Core     H264  Core Temp (Max)   IRQ/s      RX B/s      TX B/s  GPUMem Free   %user   %nice %system   %idle %iowait    %irq  %s/irq  %total  Memory Free/Used(SwUse)
========  =======  =======  =======  ===============  ======  ==========  ==========  ===========  ======  ======  ======  ======  ======  ======  ======  ======  =======================
05:28:52  1000Mhz   500Mhz     0Mhz  65.91C (65.91C)     805       1,028       9,746  183M ( 77%)   12.16   36.48   54.72    0.00    0.00    0.00    0.00  100.00  287,240 kB/24.9%( 0.1%)
05:29:02  1000Mhz   499Mhz     0Mhz  64.83C (65.91C)     760          72         106  183M ( 77%)   13.90    0.30    1.38   82.00    0.00    0.00    0.00   18.00  287,240 kB/24.9%( 0.1%)
05:29:12  1000Mhz   500Mhz     0Mhz  64.83C (65.91C)     759          83         102  183M ( 77%)   13.66    0.49    1.47   70.09   12.29    0.00    0.10   29.91  287,232 kB/24.9%( 0.1%)
05:29:22  1000Mhz   500Mhz     0Mhz  64.83C (65.91C)     759          68         108  183M ( 77%)   14.64    0.49    1.28   82.35    0.00    0.00    0.00   17.65  287,232 kB/24.9%( 0.1%)
05:29:32  1000Mhz   500Mhz     0Mhz  64.83C (65.91C)     760         134         119  183M ( 77%)   14.05    0.49    1.28   82.45    0.00    0.00    0.00   17.55  287,232 kB/24.9%( 0.1%)
05:29:42   999Mhz   500Mhz     0Mhz  64.83C (65.91C)     761         146         130  183M ( 77%)   14.86    0.78    2.05   81.35    0.00    0.00    0.00   18.65  287,232 kB/24.9%( 0.1%)
05:29:53  1000Mhz   500Mhz     0Mhz  65.91C (65.91C)     760          81         117  183M ( 77%)   14.97    0.49    1.27   82.28    0.00    0.00    0.00   17.72  287,232 kB/24.9%( 0.1%)
05:30:03   999Mhz   500Mhz     0Mhz  65.91C (65.91C)     759          88         102  183M ( 77%)   14.55    0.49    1.57   82.06    0.00    0.00    0.00   17.94  287,232 kB/24.9%( 0.1%)
05:30:13  1000Mhz   500Mhz     0Mhz  65.37C (65.91C)     759          63         102  183M ( 77%)   14.25    0.49    1.28   82.47    0.00    0.00    0.00   17.53  287,232 kB/24.9%( 0.1%)
05:30:23  1000Mhz   500Mhz     0Mhz  65.91C (65.91C)     760          90         107  183M ( 77%)   14.06    0.39    1.57   82.30    0.00    0.00    0.00   17.70  287,232 kB/24.9%( 0.1%)
05:30:33  1000Mhz   500Mhz     0Mhz  64.83C (65.91C)     759          88         102  183M ( 77%)   14.58    0.30    1.58   82.43    0.00    0.00    0.00   17.57  287,232 kB/24.9%( 0.1%)
05:30:44   999Mhz   500Mhz     0Mhz  65.37C (65.91C)     761         188         145  183M ( 77%)   14.25    0.69    1.97   81.66    0.00    0.00    0.00   18.34  287,232 kB/24.9%( 0.1%)
05:30:54  1000Mhz   500Mhz     0Mhz  64.83C (65.91C)     760          97         112  183M ( 77%)   13.69    0.49    1.48   82.32    0.00    0.00    0.00   17.68  287,232 kB/24.9%( 0.1%)
```
