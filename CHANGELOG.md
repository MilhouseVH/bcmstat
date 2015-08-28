#Changelog

##Version 0.2.8 (28/08/2015)
* Fix: Cosmetic

##Version 0.2.7 (28/08/2015)
* Chg: Update way in which `over_volatage_sdram` is determined. Now take the maximum measured voltage - `sdram_p` (pysical), `sdram_c` (controller) and `sdram_i` (IO]) - then calculate the sdram over voltage offset that would be required to achieve this voltage. This method does result in a non-overclocked RPi2 showing +1, as `over_volatage_sdram_p` is slightly overclocked by default.

##Version 0.2.6 (13/08/2015)
* Chg: More tweaks: support disable_auto_turbo

##Version 0.2.5 (13/08/2015)
* Chg: Small tweak to support 300Mhz core/gpu freq dynamic overclock when using "stock" clocks

##Version 0.2.4 (26/07/2015)
* Fix: And use those correct values when colourising output...

##Version 0.2.3 (26/07/2015)
* Fix: More accurately report core/h264 max freq (take gpu_freq into consideration)

##Version 0.2.2 (01/05/2015)
* Fix: Python3 compatibility - closes #3

##Version 0.2.1 (19/03/2015)
* Chg: Cosmetic - correct help description of core options`p`/`P`

##Version 0.2.0 (02/02/2015)
* Chg: Add `W` option in place of `F` to force downloads

##Version 0.1.9 (31/01/2015)
* Add: Show per-CPU load with `-p`
* Add: Include CPU type and quantity in summary section
* Fix: Take multiple CPUs into consideration when calculating system load
* Chg: Cosmetic, adjust width of Min Freq/Max Freq/Voltages to account for extra decimal on voltage
* Chg: Cosmetic, reduce spacing between columns to increase data density

##Version 0.1.8 (18/07/2014)
* Chg: Also look for config in `~/.config/bcmstat.conf` if not found elsewhere (ie. `~/.bcmstat.conf`)

##Version 0.1.7 (18/07/2014)
* Chg: Don't perform auto-update if running from a read-only filesystem

##Version 0.1.6 (19/06/2014)
* Fix: Support hex encoded integers in call to `vcgencmd get_config int`
* Fix: When available, use `vcgencmd get_mem [reloc_total|reloc|malloc_total|malloc]` calls rather than `vcdbg reloc` which suffers from cache coherency issues
* Add: New `f` option to display malloc gpu memory (`g` already shows reloc memory). Contrary option is `F` to disable malloc display.
* Chg: Invert interpretation of the `s` and `S` (swap memory) options, these seem to have been interpreted the wrong way around...

##Version 0.1.5 (06/04/2014)
* Fix: Store tmCore/TMAX as float not int to avoid loss of precision - thanks g7ruh. Closes #1

##Version 0.1.4 (14/02/2014)
* Add: Display peak IRQ, RX and TX values when terminating bcmstat.sh with ctrl-c

##Version 0.1.3 (13/02/2014)
* Chg: Use `vcgencmd get_mem gpu` and `vcgencmd get_mem arm` to calculate GPU/ARM split, and total available RAM.

##Version 0.1.2 (09/02/2014)
* Detect XBian

##Version 0.1.1 (26/01/2014)
* Add: Include "SwUse" (Swap Used %) in memory statistics if swap memory is enabled

##Version 0.1.0 (25/01/2014)
* Add: Include Swap allocation (if swap is enabled) in summary information

##Version 0.0.9 (23/01/2014)
* Fix: Show correct Core/SDRAM frequency when not overclocked (or when underclocked)
* Add: Min/Max H264 frequency

##Version 0.0.8 (21/01/2014)
* Chg: Small change to filter on interface data, making it less likely to be ambiguous
* Chg: Improve interface name validation

##Version 0.0.7 (06/01/2014)
* Chg: Tweak Raspbmc/Raspbian identification

##Version 0.0.6 (05/01/2014)
* Initial github release
* Add: Add self-update options (V, U, F, C)
