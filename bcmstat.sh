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
# to run at default/normal priority (ie. don't re-nice), or M to run at
# maximum priority (and minimum niceness, -20).
#
################################################################################
from __future__ import print_function
import os, sys, datetime, time, errno, subprocess, re, getpass
import platform, socket, urllib2, hashlib

VCGENCMD = None
VCDBGCMD = None
GPU_ALLOCATED_R = None
GPU_ALLOCATED_M = None
SUDO = ""
TMAX = 0.0
COLOUR = False
SYSINFO = {}

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
    if ignore_error:
      return None
    else:
      raise
    
def find_vcgencmd_vcdbg():
  global VCGENCMD, VCDBGCMD, VCGENCMD_GET_MEM

  for file in [runcommand("which vcgencmd", ignore_error=True), "/usr/bin/vcgencmd", "/opt/vc/bin/vcgencmd"]:
    if file and os.path.exists(file) and os.path.isfile(file) and os.access(file, os.X_OK):
      VCGENCMD = file
      break

  for file in [runcommand("which vcdbg", ignore_error=True), "/usr/bin/vcgdbg", "/opt/vc/bin/vcdbg"]:
    if file and os.path.exists(file) and os.path.isfile(file) and os.access(file, os.X_OK):
      VCDBGCMD = file
      break

  # Determine if we have reloc/malloc get_mem capability
  VCGENCMD_GET_MEM = False
  if VCGENCMD:
    if vcgencmd("get_mem reloc_total") != "0M" or vcgencmd("get_mem reloc") != "0M":
      VCGENCMD_GET_MEM = True

def vcgencmd(args, split=True):
  global VCGENCMD
  if split:
    return grep("", runcommand("%s %s" % (VCGENCMD, args)), 1, split_char="=")
  else:
    return runcommand("%s %s" % (VCGENCMD, args))

def vcgencmd_items(args, isInt=False):
  d = {}
  for l in [x.split("=") for x in vcgencmd(args, split=False).split("\n")]:
    if not isInt:
      d[l[0]] = l[1]
    elif l[1][:2] == "0x":
      d[l[0]] = int(l[1], 16)
    else:
      d[l[0]] = int(l[1])

  return d

def vcdbg(args):
  global VCDBGCMD, SUDO
  return runcommand("%s%s %s" % (SUDO, VCDBGCMD, args))

def readfile(infile):
  if os.path.exists(infile):
    with open(infile, 'r') as stream:
        return stream.read()[:-1]
  else:
    return ""

def grep(match_string, input_string, field=None, head=None, tail=None, split_char=" ", case_sensitive=True, defaultvalue=None):

  re_flags = 0 if case_sensitive else re.IGNORECASE

  lines = []

  for line in [x for x in input_string.split("\n") if re.search(match_string, x, flags=re_flags)]:
    aline = re.sub("%s+" % split_char, split_char, line.strip()).split(split_char)
    if field is not None:
      if len(aline) > field:
        lines.append(aline[field])
    else:
      lines.append(split_char.join(aline))

    # Don't process any more lines than we absolutely have to
    if head and not tail and len(lines) >= head:
      break

  if head: lines = lines[:head]
  if tail: lines = lines[-tail:]

  if defaultvalue and lines == []:
    return defaultvalue
  else:
    return "\n".join(lines)

# grep -v - return everything but the match string
def grepv(match_string, input_string, field=None, head=None, tail=None, split_char=" ", case_sensitive=False):
  return grep(r"^((?!%s).)*$" % match_string, input_string, field, head, tail, split_char, case_sensitive)

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
  number = compare if compare is not None else display

  if COLOUR:
    if red > green:
      if number >= red:
        return "%s%s%s" % ("\033[0;31m", nformat % cnum, "\033[0m")
      elif yellow is not None and number >= yellow:
        return "%s%s%s" % ("\033[0;33m", nformat % cnum, "\033[0m")
      elif number >= green:
        return "%s%s%s" % ("\033[0;32m", nformat % cnum, "\033[0m")
    else:
      if number <= red:
        return "%s%s%s" % ("\033[0;31m", nformat % cnum, "\033[0m")
      elif yellow is not None and number <= yellow:
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

def minmax(min, max, value):
  if value < min:
    return min
  elif value > max:
    return max
  else:
    return value

# Collect processor stats once per loop, so that consistent stats are
# used when calculating total system load and individual core loads
def getProcStats(storage):
  storage[2] = storage[1]

  cores = {}
  for core in grep("^cpu[0-9]*", readfile("/proc/stat")).split("\n"):
    items = core.split(" ")
    jiffies = []
    for jiffy in items[1:]:
      jiffies.append(int(jiffy))
    cores[items[0]] = jiffies
  storage[1] = (time.time(), cores)

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime

    cores = {}
    for core in s1[1]:
      if core in s2[1]:
        jiffies = []
        for i in range(0, 10):
          jiffies.append((int(s1[1][core][i]) - int(s2[1][core][i])) / dTime)
        cores[core] = jiffies
    storage[0] = (dTime, cores)

# Total system load
def getCPULoad(storage, proc, sysinfo):
  if proc[2][0] != 0:
    dTime = proc[0][0]
    core = proc[0][1]["cpu"]
    nproc = sysinfo["nproc"]
    c = []
    for i in range(0, 10):
      c.append(minmax(0, 100, (core[i] / nproc)))
    storage[0] = (dTime, [c[0], c[1], c[2], c[3], c[4], c[5], c[6], 100 - c[3]])

# Individual core loads
def getCoreStats(storage, proc):
  if proc[2][0] != 0:
    dTime = proc[0][0]
    load = []
    for core in sorted(proc[0][1]):
      if core == "cpu": continue
      load.append((core, 100 - minmax(0, 100, proc[0][1][core][3])))
    storage[0] = (dTime, load)

def getNetwork(storage, interface):
  storage[2] = storage[1]
  storage[1] = (time.time(), grep("^[ ]*%s:" % interface, readfile("/proc/net/dev")))

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
  tCore = float(readfile("/sys/class/thermal/thermal_zone0/temp"))
  tCore = 0 if tCore < 0 else tCore
  TMAX  = tCore if (tCore > TMAX and tCore < 85000) else TMAX

  storage[2] = storage[1]
  storage[1] = (time.time(),
                [int(vcgencmd("measure_clock arm")),
                 int(vcgencmd("measure_clock core")),
                 int(vcgencmd("measure_clock h264")),
                 tCore,
                 TMAX])

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

  if SWAPTOTAL != 0:
    SWAPUSED = (1-(float(SWAPFREE)/float(SWAPTOTAL)))*100
  else:
    SWAPUSED = None

  storage[2] = storage[1]
  storage[1] = (time.time(), [MEMTOTAL, MEMFREE, MEMUSED, SWAPUSED])

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime
    storage[0] = (dTime, [s1[1][0], s1[1][1], s1[1][2], s1[1][2] - s2[1][2], s1[1][3]])

def getGPUMem(storage, STATS_GPU_R, STATS_GPU_M):
  global GPU_ALLOCATED_R, GPU_ALLOCATED_M, VCGENCMD_GET_MEM

  if VCGENCMD_GET_MEM:
    if not GPU_ALLOCATED_R:
      GPU_ALLOCATED_R = tobytes(vcgencmd("get_mem reloc_total"))
      GPU_ALLOCATED_M = tobytes(vcgencmd("get_mem malloc_total"))
    freemem_r = vcgencmd("get_mem reloc") if STATS_GPU_R else ""
    freemem_m = vcgencmd("get_mem malloc") if STATS_GPU_M else ""
  else:
    vcgencmd("cache_flush")

    # Get gpu memory data. We only need to process a few lines near the top so
    # ignore individual memory block details by truncating data to 512 bytes.
    gpudata = vcdbg("reloc")[:512]

    if not GPU_ALLOCATED_R:
      GPU_ALLOCATED_R = tobytes(grep("total space allocated", gpudata, 4, head=1)[:-1])
      GPU_ALLOCATED_M = 0

    freemem_r = grep("free memory in", gpudata, 0, head=1)
    freemem_m = ""

  data = {}
  if STATS_GPU_R:
    if freemem_r == "": 
      freemem_r = "???"
      bfreemem_r = 0
      percent_free_r = 0
    else:
      bfreemem_r = tobytes(freemem_r)
      percent_free_r = (float(bfreemem_r)/float(GPU_ALLOCATED_R))*100
    data["reloc"] = [freemem_r, bfreemem_r, int(percent_free_r), GPU_ALLOCATED_R]

  if STATS_GPU_M:
    if freemem_m == "": 
      freemem_m = "???"
      bfreemem_m = 0
      percent_free_m = 0
    else:
      bfreemem_m = tobytes(freemem_m)
      percent_free_m = (float(bfreemem_m)/float(GPU_ALLOCATED_M))*100
    data["malloc"] = [freemem_m, bfreemem_m, int(percent_free_m), GPU_ALLOCATED_M]

  storage[0] = (time.time(), data)

def ceildiv(a, b):
  return -(-a // b)

def MHz(value, fwidth, cwidth):
  return ("%*dMHz" % (fwidth, value)).center(cwidth)

def getsysinfo():
  sysinfo = {}

  VCG_INT = vcgencmd_items("get_config int", isInt=True)

  sysinfo["nproc"]      = len(grep("^processor", readfile("/proc/cpuinfo")).split("\n"))
  sysinfo["arm_min"]    = int(int(readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"))/1000)
  sysinfo["arm_max"]    = int(int(readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"))/1000)
  sysinfo["core_max"]   = VCG_INT.get("core_freq",250)
  sysinfo["h264_max"]   = VCG_INT.get("h264_freq", 250)
  sysinfo["sdram_max"]  = VCG_INT.get("sdram_freq", 400)
  sysinfo["arm_volt"]   = VCG_INT.get("over_voltage", 0)
  sysinfo["sdram_volt"] = VCG_INT.get("over_voltage_sdram", 0)
  sysinfo["temp_limit"] = VCG_INT.get("temp_limit", 85)
  sysinfo["force_turbo"]= (VCG_INT.get("force_turbo", 0) != 0)

  if sysinfo["force_turbo"]:
    core_min = sysinfo["core_max"]
  else:
    core_min = 250
    core_min = sysinfo["core_max"] if sysinfo["core_max"] < core_min else core_min
  sysinfo["core_min"] = core_min

  # Calculate thresholds for red/yellow/green colour
  arm_min = sysinfo["arm_min"] - 10
  if sysinfo["arm_max"] <= 700:
    # Should never reach this figure...
    arm_max = 1e6
  else:
    arm_max = sysinfo["arm_max"] - 5

  core_min = sysinfo["core_min"] - 10
  if sysinfo["core_max"] <= 250:
    core_max = 1e6
  else:
    core_max = sysinfo["core_max"] - 5

  limits = {}
  limits["arm_min"] = arm_min
  limits["arm_max"] = arm_max
  limits["core_min"] = core_min
  limits["core_max"] = core_max
  sysinfo["limits"] = limits

  return sysinfo

def ShowConfig(nice_value, priority_desc, sysinfo, args):
  global VCGENCMD, VERSION

  BOOTED = datetime.datetime.fromtimestamp(int(grep("btime", readfile("/proc/stat"), 1))).strftime('%c')

  MEM_ARM = int(vcgencmd("get_mem arm")[:-1])
  MEM_GPU = int(vcgencmd("get_mem gpu")[:-1])
  MEM_MAX = MEM_ARM + MEM_GPU

  SWAP_TOTAL = int(grep("SwapTotal", readfile("/proc/meminfo"), field=1, defaultvalue="0"))

  VCG_INT    = vcgencmd_items("get_config int", isInt=True)

  NPROC      = sysinfo["nproc"]
  ARM_MIN    = sysinfo["arm_min"]
  ARM_MAX    = sysinfo["arm_max"]
  CORE_MIN   = sysinfo["core_min"]
  CORE_MAX   = sysinfo["core_max"]
  H264_MAX   = sysinfo["h264_max"]
  SDRAM_MAX  = sysinfo["sdram_max"]
  ARM_VOLT   = sysinfo["arm_volt"]
  SDRAM_VOLT = sysinfo["sdram_volt"]
  TEMP_LIMIT = sysinfo["temp_limit"]
  FORCE_TURBO= sysinfo["force_turbo"]
  vCore      = vcgencmd("measure_volts core")
  vRAM       = vcgencmd("measure_volts sdram_c")
  GOV        = readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
  FIRMWARE   = ", ".join(grepv("Copyright", vcgencmd("version", split=False)).replace(", ","").split("\n")).replace(" ,",",")

  OTHER_VARS = ["temp_limit=%d" % TEMP_LIMIT]
  for item in ["force_turbo", "initial_turbo", "avoid_pwm_pll",
               "hdmi_force_hotplug", "hdmi_force_edid_audio", "no_hdmi_resample"]:
    if VCG_INT.get(item, 0) != 0:
      OTHER_VARS.append("%s=%d" % (item, VCG_INT.get(item, 0)))

  CODECS = []
  for codec in ["H264", "WVC1", "MPG2", "VP8", "VORBIS", "MJPG", "DTS", "DDP"]:
    if vcgencmd("codec_enabled %s" % codec) == "enabled":
      CODECS.append(codec)
  CODECS = CODECS if CODECS else ["none"]

  nv = "%s%d" % ("+" if nice_value > 0 else "", nice_value)

  SWAP_MEM = "" if SWAP_TOTAL == 0 else " plus %dMB Swap" % int(ceildiv(SWAP_TOTAL, 1024))
  ARM_ARCH = grep("^model name", readfile("/proc/cpuinfo"), field=2, head=1)[0:5]

  print("  Config: v%s, args \"%s\", priority %s (%s)" % (VERSION, " ".join(args), priority_desc, nv))
  print("     CPU: %d x %s core%s available, using %s governor" % (NPROC, ARM_ARCH, "s"[NPROC==1:], GOV))
  print("  Memory: %sMB (split %sMB ARM, %sMB GPU)%s" % (MEM_MAX, MEM_ARM, MEM_GPU, SWAP_MEM))
  print("HW Block: | %s | %s | %s | %s |" % ("ARM".center(7), "Core".center(6), "H264".center(6), "SDRAM".center(11)))
  print("Min Freq: | %s | %s | %s | %s |" % (MHz(ARM_MIN,4,7), MHz(CORE_MIN,3,6), MHz(0,3,6),        MHz(SDRAM_MAX,3,11)))
  print("Max Freq: | %s | %s | %s | %s |" % (MHz(ARM_MAX,4,7), MHz(CORE_MAX,3,6), MHz(H264_MAX,3,6), MHz(SDRAM_MAX,3,11)))

  v1 = "%d, %s" % (ARM_VOLT, vCore)
  v2 = "%d, %s" % (SDRAM_VOLT, vRAM)
  v1 = "+%s" % v1 if ARM_VOLT > 0 else v1
  v2 = "+%s" % v2 if SDRAM_VOLT > 0 else v2
  print("Voltages: | %s | %s |" % (v1.center(25), v2.center(11)))

  # Chop "Other" properties up into multiple lines of limited length strings
  line = ""
  lines = []
  for item in OTHER_VARS:
    if (len(line) + len(item)) <= 80:
      line = item if line == "" else "%s, %s" % (line, item)
    else:
      lines.append(line)
      line = ""
  if line: lines.append(line)
  c=0
  for l in lines:
    c += 1
    if c == 1:
      print("   Other: %s" % l)
    else:
      print("          %s" % l)

  print("Firmware: %s" % FIRMWARE)
  print("  Codecs: %s" % " ".join(CODECS))
  printn("  Booted: %s" % BOOTED)

def ShowHeadings(display_flags, sysinfo):
  HDR1 = "Time         ARM    Core    H264 Core Temp (Max)  IRQ/s     RX B/s     TX B/s"
  HDR2 = "======== ======= ======= ======= =============== ====== ========== =========="

  if display_flags["gpu_reloc"]:
    if display_flags["gpu_malloc"]:
      HDR1 = "%s Reloc  Free" % HDR1
    else:
      HDR1 = "%s GPUMem Free" % HDR1
    HDR2 = "%s ===========" % HDR2

  if display_flags["gpu_malloc"]:
    HDR1 = "%s Malloc Free" % HDR1
    HDR2 = "%s ===========" % HDR2

  if display_flags["cpu_mem"]:
    HDR1 = "%s  %%user  %%nice   %%sys  %%idle  %%iowt   %%irq %%s/irq %%total" % HDR1
    HDR2 = "%s ====== ====== ====== ====== ====== ====== ====== ======" % HDR2

  if display_flags["cpu_cores"]:
    for i in range(0, sysinfo["nproc"]):
      HDR1 = "%s   cpu%d" % (HDR1, i)
      HDR2 = "%s ======" % HDR2

  if display_flags["cpu_mem"]:
    HDR1 = "%s Memory Free/Used" % HDR1
    HDR2 = "%s ================" % HDR2
    if display_flags["swap"]:
      HDR1 = "%s(SwUse)" % HDR1
      HDR2 = "%s=======" % HDR2

  printn("%s\n%s" % (HDR1, HDR2))

def ShowStats(display_flags, sysinfo, bcm2385, irq, network, cpuload, memory, gpumem, cores):
  global ARM_MIN, ARM_MAX

  now = datetime.datetime.now()
  TIME = "%02d:%02d:%02d" % (now.hour, now.minute, now.second)

  limits = sysinfo["limits"]
  arm_min = limits["arm_min"]
  arm_max = limits["arm_max"] 
  core_min = limits["core_min"]
  core_max = limits["core_max"]

  LINE = "%s %s %s %s %s (%s) %s %s %s" % \
           (TIME,
            colourise(bcm2385[0]/1000000, "%4dMhz", arm_min,     None,  arm_max, False),
            colourise(bcm2385[1]/1000000, "%4dMhz",core_min,     None, core_max, False),
            colourise(bcm2385[2]/1000000, "%4dMhz",       0,      200,      300, False),
            colourise(bcm2385[3]/1000,    "%5.2fC",    50.0,     70.0,     80.0, False),
            colourise(bcm2385[4]/1000,    "%5.2fC",    50.0,     70.0,     80.0, False),
            colourise(irq[0],             "%6s",        500,     2500,     5000, True),
            colourise(network[0],         "%10s",     0.5e6,    2.5e6,    5.0e6, True),
            colourise(network[1],         "%10s",     0.5e6,    2.5e6,    5.0e6, True))

  if display_flags["gpu_reloc"]:
    data = gpumem["reloc"]
    LINE = "%s %s (%s)" % \
             (LINE,
              colourise(data[0],  "%4s",   70, 50, 30, False, compare=data[2]),
              colourise(data[2],  "%3d%%", 70, 50, 30, False, compare=data[2]))

  if display_flags["gpu_malloc"]:
    data = gpumem["malloc"]
    LINE = "%s %s (%s)" % \
             (LINE,
              colourise(data[0],  "%4s",   70, 50, 30, False, compare=data[2]),
              colourise(data[2],  "%3d%%", 70, 50, 30, False, compare=data[2]))

  if display_flags["cpu_mem"]:
    LINE = "%s %s %s %s %s %s %s %s %s" % \
             (LINE,
              colourise(cpuload[0], "%6.2f",    30, 50, 70, False),
              colourise(cpuload[1], "%6.2f",    10, 20, 30, False),
              colourise(cpuload[2], "%6.2f",    30, 50, 70, False),
              colourise(cpuload[3], "%6.2f",    70, 50, 30, False),
              colourise(cpuload[4], "%6.2f",     2,  5, 10, False),
              colourise(cpuload[5], "%6.2f",     2,  5, 10, False),
              colourise(cpuload[6], "%6.2f",   7.5, 15, 20, False),
              colourise(cpuload[7], "%6.2f",    30, 50, 70, False))

  if display_flags["cpu_cores"]:
    for core in cores:
      LINE = "%s %s" % (LINE, colourise(core[1], "%6.2f",    30, 50, 70, False))

  if display_flags["cpu_mem"]:
    LINE = "%s %s/%s" % \
             (LINE,
              colourise(memory[1],  "%7s kB",   60, 75, 85, True,  compare=memory[2]),
              colourise(memory[2],  "%4.1f%%",  60, 75, 85, False, compare=memory[2]))

    # Swap memory
    if display_flags["swap"] and memory[4] is not None:
      LINE = "%s(%s)" % \
              (LINE,
               colourise(memory[4],  "%4.1f%%",  1,  5, 15, False, compare=memory[4]))

  printn("\n%s" % LINE)

def ShowHelp():
  print("Usage: %s [c|m] [d#] [H#] [i <iface>] [L|N|M] [x|X] [p|P] [g|G] [f|F] [s|S] [q|Q] [V|U|W|C] [h]" % os.path.basename(__file__))
  print()
  print("c        Colourise output (white: minimal load or usage, then ascending through green, amber and red).")
  print("m        Monochrome output (no colourise)")
  print("d #      Specify interval (in seconds) between each iteration - default is 2")
  print("H #      Header every n iterations (0 = no header, default is 30)")
  print("i iface  Monitor network interface other than the default eth0, eg. br1")
  print("L        Run at lowest priority (nice +20) - default")
  print("N        Run at normal priority (nice 0)")
  print("M        Run at maximum priority (nice -20)")
  print("x/X      Do (x)/don't (X) monitor additional CPU load and memory usage stats")
  print("p/P      Do (p)/don't (P) monitor individual core load stats (when core count > 1)")
  print("g/G      Do (g)/don't (G) monitor additional GPU memory stats (reloc memory)")
  print("f/F      Do (f)/don't (F) monitor additional GPU memory stats (malloc memory)")
  print("s/S      Do (s)/don't (S) include any available swap memory when calculating memory statistics")
  print("q/Q      Do (q)/don't (Q) suppress configuraton information")
  print()
  print("V        Check version")
  print("U        Update to latest version if an update is available")
  print("W        Force update to latest version")
  print("C        Disable auto-update")
  print()
  print("h        Print this help")
  print()
  print("Set default properties in ~/.bcmstat.conf")
  print()
  print("Note: Default behaviour is to run at lowest possible priority (L) unless N or M specified.")


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
      printout("NOTICE - A new version (v%s) of this script is available." % remoteVersion)
      printout("NOTICE - Use the \"U\" option to apply update.")
    else:
      printerr("FATAL: Unable to update current file, check you have write access")
    return False

  printout("Successfully updated from v%s to v%s" % (VERSION, remoteVersion))
  return True

def get_latest_version():
  global GITHUB, ANALYTICS, VERSION

  DIST = "Other"
  if os.path.exists("/etc/openelec-release"):
    DIST = "OpenELEC"
  else:
    etc_issue = readfile("/etc/issue")
    if etc_issue:
      if grep("raspbian", etc_issue, head=1, case_sensitive=False):
        DIST = "Raspbian"
      elif grep("raspbmc", etc_issue, head=1, case_sensitive=False):
        DIST = "Raspbmc"
      elif grep("xbian", etc_issue, head=1, case_sensitive=False):
        DIST = "XBian"

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
  if remoteVersion is None or remoteHash is None:
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
  global PEAKVALUES
  global VCGENCMD_GET_MEM

  GITHUB = "https://raw.github.com/MilhouseVH/bcmstat/master"
  ANALYTICS = "http://goo.gl/edu1jG"
  VERSION = "0.2.1"

  INTERFACE = "eth0"
  DELAY = 2
  HDREVERY = 30

  COLOUR = False
  QUIET = False
  NICE_ADJUST = +20
  INCLUDE_SWAP = True

  STATS_CPU_MEM = False
  STATS_CPU_CORE= False
  STATS_GPU_R = False
  STATS_GPU_M = False

  CHECK_UPDATE = True

  # Read default settings from config file
  # Can be overidden by command line.
  oargs = args
  config1 = os.path.expanduser("~/.bcmstat.conf")
  config2 = os.path.expanduser("~/.config/bcmstat.conf")
  if os.path.exists(config1):
    args.insert(0, readfile(config1))
  elif os.path.exists(config2):
    args.insert(0, readfile(config2))

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
      STATS_GPU_R = True
    elif a1 == "G":
      STATS_GPU_R = False

    elif a1 == "f":
      STATS_GPU_M = True
    elif a1 == "F":
      STATS_GPU_M = False

    elif a1 == "x":
      STATS_CPU_MEM = True
    elif a1 == "X":
      STATS_CPU_MEM = False

    elif a1 == "p":
      STATS_CPU_CORE= True
    elif a1 == "P":
      STATS_CPU_CORE= False

    elif a1 == "s":
      INCLUDE_SWAP = True
    elif a1 == "S":
      INCLUDE_SWAP = False

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
    elif a1 == "W":
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
    path = os.path.realpath(__file__)
    dir = os.path.dirname(path)
    if os.access(dir, os.W_OK):
      autoUpdate(oargs)

  # Do we need sudo to raise process priority or run vcdbg?
  if getpass.getuser() != "root": SUDO = "sudo "

  # Find out where vcgencmd/vcdbg binaries are...
  find_vcgencmd_vcdbg()

  SWAP_ENABLED = (int(grep("SwapTotal", readfile("/proc/meminfo"), field=1, defaultvalue="0")) != 0)

  # Renice self
  if NICE_ADJUST < 0:
    PRIO_D = "maximum"
  elif NICE_ADJUST == 0:
    PRIO_D = "normal"
  else:
    PRIO_D = "lowest"

  try:
    NICE_V = os.nice(NICE_ADJUST)
  except OSError:
    runcommand("%srenice -n %d -p %d" % (SUDO, NICE_ADJUST, os.getpid()))
    NICE_V = os.nice(0)

  # Collect basic system configuration
  sysinfo = getsysinfo()
  STATS_CPU_CORE = False if sysinfo["nproc"] < 2 else STATS_CPU_CORE

  if not QUIET:
    ShowConfig(NICE_V, PRIO_D, sysinfo, args)

  if STATS_GPU_M and not VCGENCMD_GET_MEM:
    msg="WARNING: malloc gpu memory stats (f) require firmware with a build date of 18 Jun 2014 (or later) - disabling"
    if QUIET:
      printerr("%s" % msg)
    else:
      printerr("\n\n%s" % msg, newLine=False)
    STATS_GPU_M = False

  #       -Delta-   -Current-  -Previous-
  IRQ = [(0, None), (0, None), (0, None)]
  NET = [(0, None), (0, None), (0, None)]
  PROC= [(0, None), (0, None), (0, None)]
  CPU = [(0, None), (0, None), (0, None)]
  BCM = [(0, None), (0, None), (0, None)]
  MEM = [(0, None), (0, None), (0, None)]
  GPU = [(0, None), (0, None), (0, None)]
  CORE= [(0, None), (0, None), (0, None)]

  getBCM2835(BCM)
  getIRQ(IRQ)
  getNetwork(NET, INTERFACE)

  if not NET[1][1]:
    printerr("\n\nError: Network interface %s is not valid!" % INTERFACE, newLine=False)
    sys.exit(2)

  if STATS_CPU_MEM or STATS_CPU_CORE:
    getProcStats(PROC)
    if STATS_CPU_MEM:
      getMemory(MEM, (SWAP_ENABLED and INCLUDE_SWAP))

  count = HDREVERY
  firsthdr = True

  display_flags = {"cpu_mem":    STATS_CPU_MEM,
                   "cpu_cores":  STATS_CPU_CORE,
                   "gpu_reloc":  STATS_GPU_R,
                   "gpu_malloc": STATS_GPU_M,
                   "swap":       (SWAP_ENABLED and INCLUDE_SWAP)}

  while [ True ]:
    if HDREVERY != 0 and count >= HDREVERY:
      if not QUIET or not firsthdr: printn("\n\n")
      ShowHeadings(display_flags, sysinfo)
      firsthdr = False
      count = 0
    count += 1

    getBCM2835(BCM)
    getIRQ(IRQ)
    getNetwork(NET, INTERFACE)

    if STATS_GPU_R or STATS_GPU_M:
      getGPUMem(GPU, STATS_GPU_R, STATS_GPU_M)

    if STATS_CPU_MEM or STATS_CPU_CORE:
      getProcStats(PROC)
      if STATS_CPU_MEM:
        getCPULoad(CPU, PROC, sysinfo)
        getMemory(MEM, (SWAP_ENABLED and INCLUDE_SWAP))
      if STATS_CPU_CORE:
        getCoreStats(CORE, PROC)

    ShowStats(display_flags, sysinfo, BCM[0][1], IRQ[0][1], NET[0][1], CPU[0][1], MEM[0][1], GPU[0][1], CORE[0][1])

    #Store peak values
    if PEAKVALUES is None:
      PEAKVALUES = {"IRQ":0, "RX":0, "TX":0}
    n = {}
    n["IRQ"] = IRQ[0][1][0] if IRQ[0][1][0] > PEAKVALUES["IRQ"] else PEAKVALUES["IRQ"]
    n["RX"]  = NET[0][1][0] if NET[0][1][0] > PEAKVALUES["RX"] else PEAKVALUES["RX"]
    n["TX"]  = NET[0][1][1] if NET[0][1][1] > PEAKVALUES["TX"] else PEAKVALUES["TX"]
    PEAKVALUES = n

    time.sleep(DELAY)

if __name__ == "__main__":
  try:
    PEAKVALUES = None
    main(sys.argv[1:])
  except (KeyboardInterrupt, SystemExit) as e:
    print()
    if PEAKVALUES:
      line = ""
      for item in PEAKVALUES: line = "%s%s%s: %s" % (line, (", " if line else ""), item, PEAKVALUES[item])
      print("Peak Values: %s" % line)
    if type(e) == SystemExit: sys.exit(int(str(e)))
