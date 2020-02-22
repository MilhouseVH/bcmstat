# Changelog

## Version 0.5.4 (22/02/2020)
* Add: Exit after n iterations option, J# (#18)

## Version 0.5.3 (21/09/2019)
* Add: RPi4 sdram defaults (thanks vegerot)
* Add: RPi4 sdram frequency query
* Fix: Remove Google `goo.gl` URL

## Version 0.5.2 (24/06/2019)
* Add: RPi4 support
* Fix: tweak free memory calculation

## Version 0.5.1 (27/10/2018)
* Add: support for human-readable memory and network values
* Fix: default frequencies

## Version 0.5.0 (07/09/2018)
* Add: 64-bit OS support

## Version 0.4.9 (14/03/2018)
* Add: Support for Pi3 Model B+
* Add: `e` option to display core voltage

## Version 0.4.8 (23/10/2017)
* Fix: Range errors

## Version 0.4.7 (03/10/2017)
* Add: Support for new models (CM3, Pi0W) and manufacturer (Sony Japan)

## Version 0.4.6 (28/08/2017)
* Fix: Crap...

## Version 0.4.5 (28/08/2017)
* Chg: Ignore invalid network interface and don't output network stats
* Fix: Support Predictable Network Interface Names in Stretch (ie. `enx<MAC>` instead of `eth0`)
* Add: If not eth0/enx interface, default to wlan0 (should work better with Pi0W)
* Closes #7

## Version 0.4.4 (17/01/2017)
* Chg: Add additional codecs

## Version 0.4.3 (05/10/2016)
* Fix: Allow for missing CPUFreq interface with kernel 4.8+ when `force_turbo=1`
* Chg: Add rounding to `measure_clock` to account for jitter

## Version 0.4.2 (14/08/2016)
* Fix: Read correct bits when logging past under-voltage/throttle events.

## Version 0.4.1 (21/06/2016)
* Chg: If using recent firmware (>2016-06-20), threshold events that occur during sleep intervals will now be detected and reported
* Add: If enabled (`-y`), report peak number of undervolt, frequency cap and throttle events

## Version 0.4.0 (13/06/2016)
* Add: Add `y`/`Y` to control display of under-voltage(U)/freq capped(F)/throttle(T) flags

## Version 0.3.9 (17/05/2016)
* Chg: Small bump to support Pi Zero Rev 1.2 and 1.3.

## Version 0.3.8 (12/03/2016)
* Add: Option `T` to disable 85C temperature limit - useful when stress testing

## Version 0.3.7 (29/02/2016)
* Add: Decode hardware revision
* Add: Pi3 support

## Version 0.3.6 (15/09/2015)
* Add: `Z` option to temporarily ignore a default configuration file
* Add: `A` option to show accumulated memory deltas (can be used in combination with `D`)

## Version 0.3.5 (14/09/2015)
* Fix: Cosmetic

## Version 0.3.4 (14/09/2015)
* Chg: Make colourised output the default. Disable with `m`
* Chg: Relocate GPU mem columns so that all memory stats are displayed along side each other (when enabled)
* Chg: Automatically include the GPU (reloc) and ARM memory stats when using option `D`, if not already enabled by `g`/`x` - results in potentially more compact and useful display (eg. `Dd10`)

## Version 0.3.3 (13/09/2015)
* Fix: Mem delta is in kB not bytes

## Version 0.3.2 (13/09/2015)
* Add: `D` option to display GPU and ARM memory deltas - memory allocation is shown as negative/red values, while memory freed will be shown as positive/green values. Continuous allocations with no sign of memory being free would suggest memory leakage.

## Version 0.3.1 (29/08/2015)
* Fix: Damn...old firmware.

## Version 0.3.0 (29/08/2015)
* Fix: Bah. Use integer maths and allow a small 50mV variance in the detected sdram voltage

## Version 0.2.9 (28/08/2015)
* Fix: Fix rounding error when sdram voltage is 1.4000V - calculated offset is 7 (from `int(7.999999)`), when should be 8.

## Version 0.2.8 (28/08/2015)
* Fix: Cosmetic

## Version 0.2.7 (28/08/2015)
* Chg: Update way in which `over_volatage_sdram` is determined. Now take the maximum measured voltage - `sdram_p` (pysical), `sdram_c` (controller) and `sdram_i` (IO]) - then calculate the sdram over voltage offset that would be required to achieve this voltage. This method does result in a non-overclocked RPi2 showing +1, as `over_volatage_sdram_p` is slightly overclocked by default.

## Version 0.2.6 (13/08/2015)
* Chg: More tweaks: support disable_auto_turbo

## Version 0.2.5 (13/08/2015)
* Chg: Small tweak to support 300Mhz core/gpu freq dynamic overclock when using "stock" clocks

## Version 0.2.4 (26/07/2015)
* Fix: And use those correct values when colourising output...

## Version 0.2.3 (26/07/2015)
* Fix: More accurately report core/h264 max freq (take gpu_freq into consideration)

## Version 0.2.2 (01/05/2015)
* Fix: Python3 compatibility - closes #3

## Version 0.2.1 (19/03/2015)
* Chg: Cosmetic - correct help description of core options`p`/`P`

## Version 0.2.0 (02/02/2015)
* Chg: Add `W` option in place of `F` to force downloads

## Version 0.1.9 (31/01/2015)
* Add: Show per-CPU load with `-p`
* Add: Include CPU type and quantity in summary section
* Fix: Take multiple CPUs into consideration when calculating system load
* Chg: Cosmetic, adjust width of Min Freq/Max Freq/Voltages to account for extra decimal on voltage
* Chg: Cosmetic, reduce spacing between columns to increase data density

## Version 0.1.8 (18/07/2014)
* Chg: Also look for config in `~/.config/bcmstat.conf` if not found elsewhere (ie. `~/.bcmstat.conf`)

## Version 0.1.7 (18/07/2014)
* Chg: Don't perform auto-update if running from a read-only filesystem

## Version 0.1.6 (19/06/2014)
* Fix: Support hex encoded integers in call to `vcgencmd get_config int`
* Fix: When available, use `vcgencmd get_mem [reloc_total|reloc|malloc_total|malloc]` calls rather than `vcdbg reloc` which suffers from cache coherency issues
* Add: New `f` option to display malloc gpu memory (`g` already shows reloc memory). Contrary option is `F` to disable malloc display.
* Chg: Invert interpretation of the `s` and `S` (swap memory) options, these seem to have been interpreted the wrong way around...

## Version 0.1.5 (06/04/2014)
* Fix: Store tmCore/TMAX as float not int to avoid loss of precision - thanks g7ruh. Closes #1

## Version 0.1.4 (14/02/2014)
* Add: Display peak IRQ, RX and TX values when terminating bcmstat.sh with ctrl-c

## Version 0.1.3 (13/02/2014)
* Chg: Use `vcgencmd get_mem gpu` and `vcgencmd get_mem arm` to calculate GPU/ARM split, and total available RAM.

## Version 0.1.2 (09/02/2014)
* Detect XBian

## Version 0.1.1 (26/01/2014)
* Add: Include "SwUse" (Swap Used %) in memory statistics if swap memory is enabled

## Version 0.1.0 (25/01/2014)
* Add: Include Swap allocation (if swap is enabled) in summary information

## Version 0.0.9 (23/01/2014)
* Fix: Show correct Core/SDRAM frequency when not overclocked (or when underclocked)
* Add: Min/Max H264 frequency

## Version 0.0.8 (21/01/2014)
* Chg: Small change to filter on interface data, making it less likely to be ambiguous
* Chg: Improve interface name validation

## Version 0.0.7 (06/01/2014)
* Chg: Tweak Raspbmc/Raspbian identification

## Version 0.0.6 (05/01/2014)
* Initial github release
* Add: Add self-update options (V, U, F, C)
