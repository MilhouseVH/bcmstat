#Changelog

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
