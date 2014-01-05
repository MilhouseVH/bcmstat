#!/usr/bin/env python
# -*- coding: utf-8 -*-

################################################################################
#
#  Copyright (C) 2014 Neil MacLeod (bcmstat.sh@nmacleod.com)
#
#  This Program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2, or (at your option)
#  any later version.
#
#  This Program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Simple utility to monitor Raspberry Pi BCM2835 SoC, network, CPU and memory statistics
#
# Usage:
#
#   ./bcmstat.py xcd10
#
# Help available with -h.
#
# Default is to run at lowest possible priority (maximum niceness, +19),
# but this can mean slow responses. To ensure more timely responses, use N
# to run at default/normal priority (ie. don't re-nice), or P to run at
# maximum priority (and minimum niceness, -20).
#
################################################################################
from __future__ import print_function
import os, sys, datetime, time, errno, subprocess, re, getpass
import platform, socket, urllib2, hashlib

VCGENCMD = None
VCDBGCMD = None
GPU_ALLOCATED = None
SUDO = ""
TMAX = 0
COLOUR = False

# Primitives
def printn(text):
  print(text, file=sys.stdout, end="")
  sys.stdout.flush()

def printout(msg, newLine=True):
  sys.stdout.write(msg)
  if newLine: sys.stdout.write("\n")
  sys.stdout.flush()

def printerr(msg, newLine=True):
  sys.stderr.write(msg)
  if newLine: sys.stderr.write("\n")
  sys.stderr.flush()

def runcommand(command, ignore_error=False):
  try:
    return subprocess.check_output(command.split(" "), stderr=subprocess.STDOUT)[:-1]
  except:
    if not ignore_error:
      raise
    
def find_vcgencmd_vcdbg():
  global VCGENCMD, VCDBGCMD

  for file in [runcommand("which vcgencmd", ignore_error=True), "/usr/bin/vcgencmd", "/opt/vc/bin/vcgencmd"]:
    if file and os.path.exists(file) and os.path.isfile(file) and os.access(file, os.X_OK):
      VCGENCMD = file
      break

  for file in [runcommand("which vcdbg", ignore_error=True), "/usr/bin/vcgdbg", "/opt/vc/bin/vcdbg"]:
    if file and os.path.exists(file) and os.path.isfile(file) and os.access(file, os.X_OK):
      VCDBGCMD = file
      break

def vcgencmd(args, split=True):
  global VCGENCMD
  if split:
    return grep("", runcommand("%s %s" % (VCGENCMD, args)), 1, split_char="=")
  else:
    return runcommand("%s %s" % (VCGENCMD, args))

def vcdbg(args):
  global VCDBGCMD, SUDO
  return runcommand("%s%s %s" % (SUDO, VCDBGCMD, args))

def readfile(infile):
  if os.path.exists(infile):
    with open(infile, 'r') as stream:
        return stream.read()[:-1]
  else:
    return ""

def grep(match_string, input_string, field=None, head=None, tail=None, split_char=" "):
  lines = []
  maxlines = None

  for line in [x for x in input_string.split("\n") if re.search(match_string, x)]:
    aline = re.sub("%s+" % split_char, split_char, line.strip()).split(split_char)
    if field != None:
      if len(aline) > field:
        lines.append(aline[field])
    else:
      lines.append(split_char.join(aline))

    # Don't process any more lines than we absolutely have to
    if head and not tail and len(lines) >= head:
      break

  if head: lines = lines[:head]
  if tail: lines = lines[-tail:]

  return "\n".join(lines)

# grep -v - return everything but the match string
def grepv(match_string, input_string, field=None, head=None, tail=None, split_char=" "):
  return grep(r"^((?!%s).)*$" % match_string, input_string, field, head, tail, split_char)

def tobytes(value):
  if value[-1:] == "M":
    return int(float(value[:-1]) * 1048576) # 1024*1024
  elif value[-1:] == "K":
    return int(float(value[:-1]) * 1024)
  else:
    return int(value)

def colourise(display, nformat, green, yellow, red, withcomma, compare=None):
  global COLOUR

  cnum = format(display, ",d") if withcomma else display
  number = compare if compare != None else display

  if COLOUR:
    if red > green:
      if number >= red:
        return "%s%s%s" % ("\033[0;31m", nformat % cnum, "\033[0m")
      elif number >= yellow:
        return "%s%s%s" % ("\033[0;33m", nformat % cnum, "\033[0m")
      elif number >= green:
        return "%s%s%s" % ("\033[0;32m", nformat % cnum, "\033[0m")
    else:
      if number <= red:
        return "%s%s%s" % ("\033[0;31m", nformat % cnum, "\033[0m")
      elif number <= yellow:
        return "%s%s%s" % ("\033[0;33m", nformat % cnum, "\033[0m")
      elif number <= green:
        return "%s%s%s" % ("\033[0;32m", nformat % cnum, "\033[0m")

  return nformat % cnum

def getIRQ(storage):
  storage[2] = storage[1]
  storage[1] = (time.time(), int(grep("dwc", readfile("/proc/interrupts"), 1)))

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime
    storage[0] = (dTime, [int((int(s1[1]) - int(s2[1]))/dTime)])

def getCPULoad(storage, ):
  storage[2] = storage[1]
  storage[1] = (time.time(), grep("", readfile("/proc/stat"), head=1))

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime

    c1 = s1[1].split(" ")
    c2 = s2[1].split(" ")
    c = []
    for i in range(1, 11):
      c.append((int(c1[i]) - int(c2[i])) / dTime)
    storage[0] = (dTime, [c[0], c[1], c[2], c[3], c[4], c[5], c[6], 100 - c[3]])

def getNetwork(storage, interface):
  storage[2] = storage[1]
  storage[1] = (time.time(), grep(interface, readfile("/proc/net/dev")))

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime

    n1 = s1[1].split(" ")
    n2 = s2[1].split(" ")
    pRX = int(n2[1])
    cRX = int(n1[1])
    pTX = int(n2[9])
    cTX = int(n1[9])
    cRX = cRX + 4294967295 if cRX < pRX else cRX
    cTX = cTX + 4294967295 if cTX < pTX else cTX
    dRX = cRX - pRX
    dTX = cTX - pTX
    storage[0] = (dTime, [int(dRX/dTime), int(dTX/dTime), dRX, dTX])

def getBCM2835(storage):
  global TMAX
  #Grab temp - ignore temps of 85C as this seems to be an occasional aberration in the reading
  tCore = int(readfile("/sys/class/thermal/thermal_zone0/temp"))
  tCore = 0 if tCore < 0 else tCore
  TMAX  = tCore if (tCore > TMAX and tCore < 85000) else TMAX

  storage[2] = storage[1]
  storage[1] = (time.time(),
                [int(vcgencmd("measure_clock arm")),
                 int(vcgencmd("measure_clock core")),
                 int(vcgencmd("measure_clock h264")),
                 int(tCore),
                 int(TMAX)])

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime
    storage[0] = (dTime, s1[1])

def getMemory(storage, include_swap):
  MEMTOTAL = 0
  MEMFREE = 0
  MEMUSED = 0
  MEMDIFF = 0
  SWAPTOTAL = 0
  SWAPFREE = 0
  SWAPCACHED= 0

  for line in readfile("/proc/meminfo").split("\n"):
    field_groups = re.search("^(.*):[ ]*([0-9]*) .*$", line)
    if field_groups.group(1) in ["MemFree", "Buffers", "Cached"]:
      MEMFREE += int(field_groups.group(2))
    elif field_groups.group(1) == "MemTotal":
      MEMTOTAL = int(field_groups.group(2))
    elif include_swap and field_groups.group(1) == "SwapTotal":
      SWAPTOTAL += int(field_groups.group(2))
    elif include_swap and field_groups.group(1) == "SwapFree":
      SWAPFREE += int(field_groups.group(2))
    elif include_swap and field_groups.group(1) == "SwapCached":
      SWAPCACHED += int(field_groups.group(2))

  MEMTOTAL += SWAPTOTAL
  MEMFREE += SWAPFREE

  MEMUSED = (1-(float(MEMFREE)/float(MEMTOTAL)))*100

  storage[2] = storage[1]
  storage[1] = (time.time(), [MEMTOTAL, MEMFREE, MEMUSED])

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime
    storage[0] = (dTime, [s1[1][0], s1[1][1], s1[1][2], s1[1][2] - s2[1][2]])

def getGPUMem(storage):
  global GPU_ALLOCATED

  vcgencmd("cache_flush")

  # Get gpu memory data. We only need to process a few lines near the top so
  # ignore individual memory block details by truncating data to 512 bytes.
  gpudata = vcdbg("reloc")[:512]

  if not GPU_ALLOCATED:
    GPU_ALLOCATED = tobytes(grep("total space allocated", gpudata, 4, head=1)[:-1])

  freemem = grep("free memory in", gpudata, 0, head=1)
  if freemem == "": 
    freemem = "???"
    bfreemem = 0
  else:
    bfreemem = tobytes(freemem)

  percent_free = (float(bfreemem)/float(GPU_ALLOCATED))*100

  storage[0] = (time.time(), [freemem, bfreemem, int(percent_free), GPU_ALLOCATED])

def ShowConfig(nice_value, priority_desc):
  global VCGENCMD

  BOOT_DIR = grep("mmcblk0p1", runcommand("mount"), field=2)
  CONFIG_TXT = readfile("%s/config.txt" % BOOT_DIR)

  BOOTED = datetime.datetime.fromtimestamp(int(grep("btime", readfile("/proc/stat"), 1))).strftime('%c')

  MEM_MAX = 512 if int(re.sub(".*: ", "", grep("Revision", readfile("/proc/cpuinfo")))[-4:],16) > 10 else 256

  MEM_GPU_XXX = grep("^[   ]*gpu_mem_%s[ =]" % MEM_MAX, CONFIG_TXT, 1, split_char="=")
  MEM_GPU_GLB = grep("^[   ]*gpu_mem[ =]", CONFIG_TXT, 1, split_char="=")
  if not MEM_GPU_GLB: MEM_GPU_GLB = 64
  MEM_GPU = MEM_GPU_XXX if MEM_GPU_XXX else MEM_GPU_GLB
  MEM_ARM = "%d" % (int(MEM_MAX) - int(MEM_GPU))

  GOV        = readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
  ARM_MIN    = int(readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"))
  ARM_MAX    = int(readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"))
  ARM_VOLT   = int(vcgencmd("get_config over_voltage"))
  CORE_MAX   = int(vcgencmd("get_config core_freq"))
  SDRAM_MAX  = int(vcgencmd("get_config sdram_freq"))
  SDRAM_VOLT = int(vcgencmd("get_config over_voltage_sdram"))
  vCore      = vcgencmd("measure_volts core")
  vRAM       = vcgencmd("measure_volts sdram_c")
  TEMP_LIMIT = vcgencmd("get_config temp_limit")
  VER        = ", ".join(grepv("Copyright", vcgencmd("version", split=False)).replace(", ","").split("\n")).replace(" ,",",")

  OTHER_VARS = "TEMP_LIMIT=%sC" % TEMP_LIMIT
  if vcgencmd("get_config force_turbo") == "1":
    OTHER_VARS = "%s, FORCE_TURBO" % OTHER_VARS
  if vcgencmd("get_config current_limit_override") == "0x5a000020":
    OTHER_VARS = "%s, CURRENT_LIMIT_OVERRIDE" % OTHER_VARS

  CODECS = []
  for codec in ["H264", "WVC1", "MPG2", "VP8", "VORBIS", "MJPG", "DTS", "DDP"]:
    if vcgencmd("codec_enabled %s" % codec) == "enabled":
      CODECS.append(codec)
  CODECS = CODECS if CODECS else ["none"]

  print("Governor: %s" % GOV)
  print("  Memory: %sMB (%sMB ARM, %sMB GPU)" % (MEM_MAX, MEM_ARM, MEM_GPU))
  print("Min Freq: %4dMhz | %4dMhz | %4dMhz" % (int(ARM_MIN/1000), 250, SDRAM_MAX))
  print("Max Freq: %4dMhz | %4dMhz | %4dMhz" % (int(ARM_MAX/1000), CORE_MAX, SDRAM_MAX))

  v1 = "%d, %s" % (ARM_VOLT, vCore)
  v2 = "%d, %s" % (SDRAM_VOLT, vRAM)
  if ARM_VOLT == 0: v1 = " %s" % v1
  if ARM_VOLT > 0:  v1 = "+%s" % v1
  if SDRAM_VOLT == 0: v2 = " %s" % v2
  if SDRAM_VOLT > 0:  v2 = "+%s" % v2
  print("Voltages:      %s    | %s" % (v1, v2))

  print("   Other: %s" % OTHER_VARS)
  print(" Version: %s" % VER)
  print("vcg path: %s" % VCGENCMD)
  print("  Codecs: %s" % " ".join(CODECS))
  print("  Booted: %s" % BOOTED)
  printn("Priority: %s (%s%d)" % (priority_desc, "+" if nice_value > 0 else "", nice_value))

def ShowHeadings(STATS_CPU_MEM, STATS_GPU):
  HDR1 = "Time          ARM     Core     h264  Core Temp (Max)   IRQ/s      RX B/s      TX B/s"
  HDR2 = "========  =======  =======  =======  ===============  ======  ==========  =========="

  if STATS_GPU:
      HDR1 = "%s  GPUMem Free" % HDR1
      HDR2 = "%s  ===========" % HDR2

  if STATS_CPU_MEM:
      HDR1 = "%s   %%user   %%nice %%system   %%idle %%iowait    %%irq  %%s/irq  %%total  Memory Free/Used" % HDR1
      HDR2 = "%s  ======  ======  ======  ======  ======  ======  ======  ======  ================" % HDR2

  printn("%s\n%s" % (HDR1, HDR2))

def ShowStats(STATS_CPU_MEM, STATS_GPU, bcm2385, irq, network, cpuload, memory, gpumem):
  now = datetime.datetime.now()
  TIME = "%02d:%02d:%02d" % (now.hour, now.minute, now.second)

  LINE = "%s  %s  %s  %s  %s (%s)  %s  %s  %s" % \
           (TIME,
            colourise(bcm2385[0]/1000000, "%4dMhz",   250,   800,   900, False),
            colourise(bcm2385[1]/1000000, "%4dMhz",     0,   200,   400, False),
            colourise(bcm2385[2]/1000000, "%4dMhz",     0,   200,   300, False),
            colourise(bcm2385[3]/1000,    "%5.2fC",  50.0,  70.0,  80.0, False),
            colourise(bcm2385[4]/1000,    "%5.2fC",  50.0,  70.0,  80.0, False),
            colourise(irq[0],             "%6s",      500,  2500,  5000, True),
            colourise(network[0],         "%10s",   0.5e6, 2.5e6, 5.0e6, True),
            colourise(network[1],         "%10s",   0.5e6, 2.5e6, 5.0e6, True))

  if STATS_GPU:
    LINE = "%s  %s (%s)" % \
             (LINE,
              colourise(gpumem[0],  "%5s",   70, 50, 30, False, compare=gpumem[2]),
              colourise(gpumem[2],  "%2d%%", 70, 50, 30, False, compare=gpumem[2]))

  if STATS_CPU_MEM:
    LINE = "%s  %s  %s  %s  %s  %s  %s  %s  %s  %s/%s" % \
             (LINE,
              colourise(cpuload[0], "%6.2f",    30, 50, 70, False),
              colourise(cpuload[1], "%6.2f",    10, 20, 30, False),
              colourise(cpuload[2], "%6.2f",    30, 50, 70, False),
              colourise(cpuload[3], "%6.2f",    70, 50, 30, False),
              colourise(cpuload[4], "%6.2f",     2,  5, 10, False),
              colourise(cpuload[5], "%6.2f",     2,  5, 10, False),
              colourise(cpuload[6], "%6.2f",   7.5, 15, 20, False),
              colourise(cpuload[7], "%6.2f",    30, 50, 70, False),
              colourise(memory[1],  "%7s kB",   60, 75, 85, True,  compare=memory[2]),
              colourise(memory[2],  "%4.1f%%",  60, 75, 85, False, compare=memory[2]))

  printn("\n%s" % LINE)

def ShowHelp():
  print("Usage: %s [c|m] [d#] [H#] [i <iface>] [L|N|M] [g|G] [x|X] [s|S] [q] [h] [V|U|F|C]" % os.path.basename(__file__))
  print()
  print("c        Colourise output (white: minimal load or usage, then ascending through green, amber and red).")
  print("m        Monochrome output (no colourise)")
  print("d #      Specify interval (in seconds) between each iteration - default is 2")
  print("H #      Header every n iterations (0 = no header, default is 30)")
  print("i iface  Monitor network interface other than the default eth0, eg. br1")
  print("L        Run with lowest priority (nice +20)")
  print("N        Run with normal priority (nice 0)")
  print("M        Run with highest possible priority (nice -20)")
  print("x/X      Do (x)/don't (X) monitor additional CPU load and memory usage stats")
  print("g/G      Do (g)/don't (G) monitor additional GPU memory stats")
  print("s/S      Do (s)/don/t (S) include any available swap memory when calculating memory statistics")
  print("q/Q      Do (q)/don't (Q) suppress configuraton inforation")
  print()
  print("V        Check version")
  print("U        Update to latest version if an update is available")
  print("F        Force update to latest version")
  print("C        Disable auto-update")
  print()
  print("h        Print this help")
  print()
  print("Set default properties in ~/.bcmstat.conf")
  print()
  print("Note: Default behaviour is to run at lowest possible priority (nice +19), unless N or P specified.")


#===================

def checkVersion(show_version=False):
  global GITHUB, VERSION

  (remoteVersion, remoteHash) = get_latest_version()

  if show_version:
    printout("Current Version: v%s" % VERSION)
    printout("Latest  Version: %s" % ("v" + remoteVersion if remoteVersion else "Unknown"))
    printout("")

  if remoteVersion and remoteVersion > VERSION:
    printout("A new version of this script is available - use the \"U\" option to automatically apply update.")
    printout("")

  if show_version:
    url = GITHUB.replace("//raw.","//").replace("/master","/blob/master")
    printout("Full changelog: %s/CHANGELOG.md" % url)

def downloadLatestVersion(args, autoupdate=False, forceupdate=False):
  global GITHUB, VERSION

  (remoteVersion, remoteHash) = get_latest_version()

  if autoupdate and (not remoteVersion or remoteVersion <= VERSION):
    return False

  if not remoteVersion:
    printerr("FATAL: Unable to determine version of the latest file, check internet and github.com are available.")
    return

  if not forceupdate and remoteVersion <= VERSION:
    printerr("Current version is already up to date - no update required.")
    return

  try:
    response = urllib2.urlopen("%s/%s" % (GITHUB, "bcmstat.sh"))
    data = response.read()
  except Exception as e:
    if autoupdate: return False
    printerr("Exception in downloadLatestVersion(): %s" % e)
    printerr("FATAL: Unable to download latest version, check internet and github.com are available.")
    return

  digest = hashlib.md5()
  digest.update(data)

  if (digest.hexdigest() != remoteHash):
    if autoupdate: return False
    printerr("FATAL: Checksum of new version is incorrect, possibly corrupt download - abandoning update.")
    return

  path = os.path.realpath(__file__)
  dir = os.path.dirname(path)

  if os.path.exists("%s%s.git" % (dir, os.sep)):
    printerr("FATAL: Might be updating version in git repository... Abandoning update!")
    return

  try:
    THISFILE = open(path, "wb")
    THISFILE.write(data)
    THISFILE.close()
  except:
    if autoupdate:
      printlog("NOTICE - A new version (v%s) of this script is available." % remoteVersion)
      printlog("NOTICE - Use the \"U\" option to apply update.")
    else:
      printerr("FATAL: Unable to update current file, check you have write access")
    return False

  printout("Successfully updated from v%s to v%s" % (VERSION, remoteVersion))
  return True

def get_latest_version():
  global GITHUB, ANALYTICS, VERSION

  if os.path.exists("/etc/openelec-release"):
    DIST = "OpenELEC"
  elif os.path.exists("/boot"):
    DIST = "Raspbian" if grep("Raspbian", readfile("/etc/issue")) != "" else "Raspbmc"
  else:
    DIST = "Other"

  # Need user agent etc. for analytics
  user_agent = "Mozilla/5.0 (%s; %s_%s; rv:%s) Gecko/20100101 Py-v%d.%d.%d.%d/1.0" % \
      (DIST, "ARM", "32", VERSION,
       sys.version_info[0], sys.version_info[1], sys.version_info[2], sys.version_info[4])

  # Construct "referer" to indicate distribution:
  USAGE = DIST

  HEADERS = []
  HEADERS.append(('User-agent', user_agent))
  HEADERS.append(('Referer', "http://www.%s" % USAGE))

  # Try checking version via Analytics URL
  (remoteVersion, remoteHash) = get_latest_version_ex(ANALYTICS, headers = HEADERS, checkerror = False)

  # If the Analytics call fails, go direct to github
  if remoteVersion == None or remoteHash == None:
    (remoteVersion, remoteHash) = get_latest_version_ex("%s/%s" % (GITHUB, "VERSION"))

  return (remoteVersion, remoteHash)

def get_latest_version_ex(url, headers=None, checkerror=True):
  GLOBAL_TIMEOUT = socket.getdefaulttimeout()
  ITEMS = (None, None)

  try:
    socket.setdefaulttimeout(5.0)

    if headers:
      opener = urllib2.build_opener()
      opener.addheaders = headers
      response = opener.open(url)
    else:
      response = urllib2.urlopen(url)

    if sys.version_info >= (3, 0):
      data = response.read().decode("utf-8")
    else:
      data = response.read()

    items = data.replace("\n","").split(" ")

    if len(items) == 2:
      ITEMS = items
    else:
      if checkerror: printerr("Bogus data in get_latest_version_ex(): url [%s], data [%s]" % (url, data))
  except Exception as e:
    if checkerror: printerr("Exception in get_latest_version_ex(): url [%s], text [%s]" % (url, e))

  socket.setdefaulttimeout(GLOBAL_TIMEOUT)
  return ITEMS

#
# Download new version if available, then replace current
# process - os.execl() doesn't return.
#
# Do nothing if newer version not available.
#
def autoUpdate(args):
  if downloadLatestVersion(args, autoupdate=True):
    argv = sys.argv
    argv.append("C")
    os.execl(sys.executable, sys.executable, *argv)

def main(args):
  global COLOUR, SUDO
  global GITHUB, ANALYTICS, VERSION

  GITHUB = "https://raw.github.com/MilhouseVH/bcmstat/master"
  ANALYTICS = "http://goo.gl/edu1jG"
  VERSION = "0.0.6"

  INTERFACE = "eth0"
  DELAY = 2
  HDREVERY = 30

  COLOUR = False
  QUIET = False
  NICE_ADJUST = +20
  INCLUDE_SWAP = True

  STATS_CPU_MEM = False
  STATS_GPU = False

  CHECK_UPDATE = True

  # Read default settings from config file
  # Can be overidden by command line.
  oargs = args
  config = os.path.expanduser("~/.bcmstat.conf")
  if os.path.exists(config):
    args.insert(0, readfile(config))

  # Crude attempt at argument parsing as I don't want use argparse
  # but instead try and keep it vaguely more shell-like, ie. -xcd10
  # rather than -x -c -d 10 etc.
  argp = [("", "")]
  i = 0
  VALUE = False
  for x in " ".join(args):
    if x == " ":
      VALUE = False
      continue

    if VALUE or (x >= "0" and x <= "9"):
      t = (argp[i][0], "%s%s" % (argp[i][1], x))
      argp[i] = t
    else:
      argp.append((x,""))
      VALUE = x in ["i", "d", "h"]
      i += 1

  del argp[0]

  for arg in argp:
    a1 = arg[0]
    a2 = arg[1]

    if a1 == "c":
      COLOUR = True
    elif a1 == "m":
      COLOUR = False
    elif a1 == "d":
      DELAY = int(a2)
    elif a1 == "H":
      HDREVERY = int(a2)

    elif a1 == "i":
      INTERFACE = a2

    elif a1 == "L":
      NICE_ADJUST = +20
    elif a1 == "N":
      NICE_ADJUST = 0
    elif a1 == "M":
      NICE_ADJUST = -20

    elif a1 == "g":
      STATS_GPU = True
    elif a1 == "G":
      STATS_GPU = False

    elif a1 == "x":
      STATS_CPU_MEM = True
    elif a1 == "X":
      STATS_CPU_MEM = False

    elif a1 == "s":
      INCLUDE_SWAP = False
    elif a1 == "S":
      INCLUDE_SWAP = True

    elif a1 == "q":
      QUIET = True
    elif a1 == "Q":
      QUIET = False

    elif a1 == "V":
      checkVersion(True)
      return
    elif a1 == "U":
      downloadLatestVersion(oargs, forceupdate=False)
      return
    elif a1 == "F":
      downloadLatestVersion(oargs, forceupdate=True)
      return
    elif a1 == "C":
      CHECK_UPDATE = False

    elif a1 == "h":
      ShowHelp()
      return

    elif a1 == "-":
      pass

    else:
      printn("Sorry, don't understand option [%s] - exiting" % a1)
      sys.exit(2)

  if CHECK_UPDATE:
    autoUpdate(oargs)

  # Do we need sudo to raise process priority or run vcdbg?
  if getpass.getuser() != "root": SUDO = "sudo "

  # Find out where vcgencmd/vcdbg binaries are...
  find_vcgencmd_vcdbg()

  # Renice self
  if NICE_ADJUST < 0:
    PRIO_D = "Highest"
  elif NICE_ADJUST == 0:
    PRIO_D = "Normal"
  else:
    PRIO_D = "Lowest"

  try:
    NICE_V = os.nice(NICE_ADJUST)
  except OSError:
    runcommand("%srenice -n %d -p %d" % (SUDO, NICE_ADJUST, os.getpid()))
    NICE_V = os.nice(0)

  if not QUIET:
    ShowConfig(NICE_V, PRIO_D)

  #       -Delta-   -Current-  -Previous-
  IRQ = [(0, None), (0, None), (0, None)]
  NET = [(0, None), (0, None), (0, None)]
  CPU = [(0, None), (0, None), (0, None)]
  BCM = [(0, None), (0, None), (0, None)]
  MEM = [(0, None), (0, None), (0, None)]
  GPU = [(0, None), (0, None), (0, None)]

  getBCM2835(BCM)
  getIRQ(IRQ)
  getNetwork(NET, INTERFACE)

  if STATS_CPU_MEM:
    getCPULoad(CPU)
    getMemory(MEM, INCLUDE_SWAP)

  count = HDREVERY
  firsthdr = True

  while [ True ]:
    if HDREVERY != 0 and count >= HDREVERY:
      if not QUIET or not firsthdr: printn("\n\n")
      ShowHeadings(STATS_CPU_MEM, STATS_GPU)
      firsthdr = False
      count = 0
    count += 1

    getBCM2835(BCM)
    getIRQ(IRQ)
    getNetwork(NET, INTERFACE)

    if STATS_GPU:
      getGPUMem(GPU)

    if STATS_CPU_MEM:
      getCPULoad(CPU)
      getMemory(MEM, INCLUDE_SWAP)

    ShowStats(STATS_CPU_MEM, STATS_GPU, BCM[0][1], IRQ[0][1], NET[0][1], CPU[0][1], MEM[0][1], GPU[0][1])

    time.sleep(DELAY)

if __name__ == "__main__":
  try:
    main(sys.argv[1:])
  except (KeyboardInterrupt, SystemExit) as e:
    print()
    if type(e) == SystemExit: sys.exit(int(str(e)))
