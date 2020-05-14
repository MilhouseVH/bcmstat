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
# Simple utility to monitor Raspberry Pi BCM283X SoC, network, CPU and memory statistics
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
import platform, socket, hashlib

if sys.version_info >= (3, 0):
  import urllib.request as urllib2
else:
  import urllib2

GITHUB = "https://raw.github.com/MilhouseVH/bcmstat/master"
VERSION = "0.5.5"

VCGENCMD = None
VCDBGCMD = None
GPU_ALLOCATED_R = None
GPU_ALLOCATED_M = None
SUDO = ""
TCMAX = 0.0
TPMAX = 0.0
LIMIT_TEMP = True
COLOUR = False
SYSINFO = {}

DEFAULT_COLS_FILTER = ["UFT", "Vcore", "ARM", "Core", "H264", "TempCore", "TempPMIC", "IRQ", "RX", "TX",
                       "CPU", "CPUuser", "CPUnice", "CPUsys", "CPUidle", "CPUiowt", "CPUirq", "CPUs/irq", "CPUtotal",
                       "GPUfree", "MEMfree", "MEMdelta", "MEMaccum"]

EXTRA_COLS_FILTER = ["V3D", "ISP"]

# [USER:8][NEW:1][MEMSIZE:3][MANUFACTURER:4][PROCESSOR:4][TYPE:8][REV:4]
# NEW          23: will be 1 for the new scheme, 0 for the old scheme
# MEMSIZE      20: 0=256M 1=512M 2=1G
# MANUFACTURER 16: 0=SONY 1=EGOMAN 2=EMBEST 3=SONY JAPAN 4=EMBEST
# PROCESSOR    12: 0=2835 1=2836 2=2837, 3=2838
# TYPE         04: 0=MODELA 1=MODELB 2=MODELA+ 3=MODELB+ 4=Pi2 MODELB 5=ALPHA 6=CM 8=Pi3 9=Pi0 10=CM3 12=Pi0W
# REV          00: 0=REV0 1=REV1 2=REV2 3=REV3

#0  Unknown
#1  pi3rev1.0       = 1<<23 | 2<<20 | 2<<12 | 8<<4 | 0<<0   = 0xa02080
#2  pi3rev1.2       = 1<<23 | 2<<20 | 2<<12 | 8<<4 | 2<<0   = 0xa02082
#3  2837 pi2 rev1.1 = 1<<23 | 2<<20 | 2<<12 | 4<<4 | 1<<0   = 0xa02041
#4  2836 pi2        = 1<<23 | 2<<20 | 1<<12 | 4<<4 | 1<<0   = 0xa01041
#5  rev1.1 B+       = 1<<23 | 1<<20 | 0<<12 | 3<<4 | 0xf<<0 = 0x90003f
#6  pi0             = 1<<23 | 1<<20 | 0<<12 | 9<<4 | 0<<0   = 0x900090
#Extras:
#7  pi1rev2.0       = 1<<23 | 1<<20 | 0<<12 | 1<<4 | 2<<0   = 0x900012
#8  2837 pi2rev1.0  = 1<<23 | 2<<20 | 2<<12 | 4<<4 | 0<<0   = 0xa01040
#9  pi0 W           = 1<<23 | 1<<20 | 0<<12 | 9<<4 | 0<<0   = 0x9000c0
#10 2837 pi2rev1.2  = 1<<23 | 2<<20 | 2<<12 | 4<<4 | 0<<0   = 0xa02042

class RPIHardware():
  def __init__(self, rev_code = None):
    self.hardware_raw = {"rev_code": 0, "bits": "", "pcb": 0, "user": 0, "new": 0, "memsize": 0, "manufacturer": 0, "processor": 0, "type": 0, "rev": 0}
    self.hardware_fmt = {"bits": "", "pcb": "", "new": "", "memsize": "", "manufacturer": "", "processor": "", "type": "", "rev": ""}

    # Note: Some of these memory sizes and processors are fictional and relate to unannounced products - logic would
    #       dictate such products may exist at some point in the future, but it's only guesswork.
    self.memsizes = ["256MB", "512MB", "1GB", "2GB", "4GB", "8GB"]
    self.manufacturers = ["Sony UK", "Egoman", "Embest", "Sony Japan", "Embest", "Stadium"]
    self.processors = ["2835", "2836", "2837", "2838", "2839", "2840"]
    self.models = ["Model A", "Model B", "Model A+", "Model B+", "Pi2 Model B", "Alpha", "CM1", "Unknown", "Pi3", "Pi0", "CM3", "Unknown", "Pi0 W", "Pi3 Model B+", "Pi3 Model A+", "Unknown", "CM3+", "Pi4 Model B"]
    self.pcbs = ["Unknown", "Pi3 Rev1.0", "Pi3 Rev1.2", "Pi2 2837 Rev1.1", "Pi2 2836", "Pi1 B+ Rev 1.1", "Pi0", "Pi1 B Rev2.0", "Pi2 (2837) Rev1.0", "Pi0 W", "Pi2 (2837) Rev1.2", "Pi3 B+"]

    self.set_rev_code(rev_code)
#    self.dump()

  # Output a pretty format... based on some guesswork, not exhaustively tested
  def __str__(self):
    #[Pi#|CM] <Model X> Rev #.# (SoC #### with ###MB RAM) manufactured by XXXXXXXXXX
    pretty = []
    if self.hardware_fmt["type"].startswith("CM"):
      pretty.append(self.hardware_fmt["type"])
    elif self.hardware_fmt["type"].startswith("Pi"):
      pretty.append(self.hardware_fmt["type"])
    else:
      pretty.append("Pi1")
      pretty.append(self.hardware_fmt["type"])

    if self.hardware_raw["pcb"] == 7: #Pi1 B r2.0
      rev = "2.0"
    else:
      rev = "1.%d" % self.hardware_raw["rev"]

    pretty.append("rev %s," % rev)
    pretty.append("BCM%s SoC with %s RAM" % (self.hardware_fmt["processor"], self.hardware_fmt["memsize"]))
    pretty.append("by %s" % self.hardware_fmt["manufacturer"])

    return " ".join(pretty)

  def dump(self):
    print("%s\n%s" % (self.hardware_raw, self.hardware_fmt))

  def bin(self, s, len = 32):
    return ("%*s" % (len, self._bin(s))).replace(" ", "0")

  def _bin(self, s):
    return str(s) if s<=1 else self._bin(s>>1) + str(s&1)

  def getbits(self, bits, lsb, len=1):
    return (bits & (((2 ** len) - 1) << lsb)) >> lsb

  def readfile(self, infile, isbinary=False):
    if not isbinary:
      if os.path.exists(infile):
        with open(infile, 'r') as stream:
          return stream.read()[:-1].split("\n")
      else:
        return ""
    else:
      if os.path.exists(infile):
        with open(infile, 'rb') as stream:
          return stream.read()
      else:
        return [-1]

  def read_rev_code(self):
    for line in self.readfile("/proc/cpuinfo", ""):
      if line.startswith("Revision\t:"):
        return "0x%s" % line.split(" ")[1]
    else:
      revision = self.readfile("/proc/device-tree/system/linux,revision", isbinary=True)
      if len(revision) == 4:
        v = (ord(revision[0]) << 24) + (ord(revision[1]) << 16) + (ord(revision[2]) << 8) + (ord(revision[3]))
      else:
        v = 0
      return '{:08x}'.format(v)

  def set_rev_code(self, rev_code):
    if rev_code is None:
      rev_code = int(self.read_rev_code(), 16)

    b = self.bin(rev_code)

    self.hardware_raw["rev_code"] = rev_code
    self.hardware_raw["bits"] = "%s %s %s %s %s %s %s" % (b[0:8], b[8:9], b[9:12], b[12:16], b[16:20], b[20:28], b[28:32])
    self.hardware_raw["user"] = self.getbits(rev_code, 24, 8)
    self.hardware_raw["new"] = self.getbits(rev_code, 23, 1)
    self.hardware_raw["memsize"] = self.getbits(rev_code, 20, 3)
    self.hardware_raw["manufacturer"] = self.getbits(rev_code, 16, 4)
    self.hardware_raw["processor"] = self.getbits(rev_code, 12, 4)
    self.hardware_raw["type"] = self.getbits(rev_code, 4, 8)
    self.hardware_raw["rev"] = self.getbits(rev_code, 0, 4)

    #http://elinux.org/RPi_HardwareHistory#Board_Revision_History
    if self.hardware_raw["type"] == 0:
      if self.hardware_raw["rev"] in [0, 1, 2, 3]:
        self.hardware_raw["new"] = 0
        self.hardware_raw["memsize"] = 0
        self.hardware_raw["processor"] = 0
        self.hardware_raw["type"] = 1
        self.hardware_raw["rev"] = 1
      elif self.hardware_raw["rev"] in [4, 5, 6]:
        self.hardware_raw["new"] = 0
        self.hardware_raw["memsize"] = 0
        self.hardware_raw["processor"] = 0
        self.hardware_raw["type"] = 1
        self.hardware_raw["rev"] = 2
      elif self.hardware_raw["rev"] in [0xd, 0xe, 0xf]:
        self.hardware_raw["new"] = 1
        self.hardware_raw["memsize"] = 1
        self.hardware_raw["processor"] = 0
        self.hardware_raw["type"] = 1
        self.hardware_raw["rev"] = 2

    pcb_base = self.hardware_raw["new"] << 23 | self.hardware_raw["memsize"] << 20 | self.hardware_raw["processor"] << 12 | self.hardware_raw["type"] << 4 | self.hardware_raw["rev"] << 0

    if pcb_base == 0xa02080:
      pcb = 1
    elif pcb_base == 0xa02082:
      pcb = 2
    elif pcb_base == 0xa02041:
      pcb = 3
    elif pcb_base == 0xa01041:
      pcb = 4
    elif pcb_base == 0xa01040:
      pcb = 8
    elif pcb_base == 0x90003f:
      pcb = 5
    elif (pcb_base & 0xfffff0) == 0x900090:
      pcb = 6
    elif pcb_base == 0x900012:
      pcb = 7
    elif (pcb_base & 0xfffff0) == 0x9000c0:
      pcb = 9
    elif (pcb_base & 0xfffff0) in [0xa22080, 0xa32082]:
      pcb = 3
    elif pcb_base == 0xa02042:
      pcb = 10
    elif pcb_base == 0xa020d0:
      pcb = 11
    else:
      pcb = 0
    self.hardware_raw["pcb"] = pcb

    self.hardware_fmt = {"pcb": "Unknown", "bits": "", "new": "", "memsize": "", "manufacturer": "Unknown", "processor": "Unknown", "type": "Unknown", "rev": ""}

    self.hardware_fmt["bits"] = self.hardware_raw["bits"]

    self.hardware_fmt["new"] = ["No", "Yes"][self.hardware_raw["new"]]
    self.hardware_fmt["memsize"] = self.memsizes[self.hardware_raw["memsize"]]

    if 0 <= self.hardware_raw["manufacturer"] < len(self.manufacturers):
      self.hardware_fmt["manufacturer"] = self.manufacturers[self.hardware_raw["manufacturer"]]

    self.hardware_fmt["processor"] = self.processors[self.hardware_raw["processor"]]

    if 0 <= self.hardware_raw["type"] < len(self.models):
      self.hardware_fmt["type"] = self.models[self.hardware_raw["type"]]

    self.hardware_fmt["rev"] = "Rev%d" % self.hardware_raw["rev"]

    if 0 <= self.hardware_raw["pcb"] < len(self.pcbs):
      self.hardware_fmt["pcb"] = self.pcbs[self.hardware_raw["pcb"]]

  def GetPiModel(self):
    if self.hardware_raw["processor"] == 0:
      return "RPi1"
    elif self.hardware_raw["processor"] == 1:
      return "RPi2"
    elif self.hardware_raw["processor"] == 2:
      return "RPi3"
    elif self.hardware_raw["processor"] == 3:
      return "RPi4"
    elif self.hardware_raw["processor"] == 4:
      return "RPi5"

  def GetBoardPCB(self):
    return self.hardware_fmt["pcb"]

  def GetMemSize(self):
    return self.hardware_fmt["memsize"]

  def GetManufacturer(self):
    return self.hardware_fmt["manufacturer"]

  def GetProcessor(self):
    return self.hardware_fmt["processor"]

  def GetType(self):
    return self.hardware_fmt["type"]

  def GetRev(self):
    return self.hardware_fmt["rev"]

  # https://www.raspberrypi.org/forums/viewtopic.php?f=63&t=147781&start=50#p972790
  def GetThresholdValues(self, storage, filter, withclear):
    keys = ["under-voltage", "arm-capped", "throttled"]

    # If withclear is supported, clear persistent bits after querying (value is "since last query")
    # The alternative value is "since boot". Always use "since boot" on first query.
    if withclear and storage[1][0] != 0:
      value = int(vcgencmd("get_throttled 0x7"), 16)
    else:
      value = int(vcgencmd("get_throttled"), 16)

    storage[2] = storage[1]
    storage[1] = (time.time(), {keys[0]: (self.getbits(value, 0, 1), self.getbits(value, 16, 1)),
                                keys[1]: (self.getbits(value, 1, 1), self.getbits(value, 17, 1)),
                                keys[2]: (self.getbits(value, 2, 1), self.getbits(value, 18, 1))})

    if storage[2][0] != 0:
      s0 = storage[0]
      s1 = storage[1]
      s2 = storage[2]
      dTime = s1[0] - s2[0]
      dTime = 1 if dTime <= 0 else dTime
      threshold = {}
      for k in keys:
        now = s1[1][k][0]
        occ = s1[1][k][1]
        prev = s0[1][k][1] if s0[0] != 0 else 0
        prev |= s2[1][k][1]
        # If an event isn't currently active but an event has occurred since the last query
        # then report it as active since the previous query
        if withclear and now == 0 and occ == 1:
          now = 1
        # Persist occurred status across queries
        threshold[k] = (now, occ | prev)
      storage[0] = (dTime, threshold)

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
    if sys.version_info >= (3, 0):
      return subprocess.check_output(command.split(" "), stderr=subprocess.STDOUT).decode("utf-8")[:-1]
    else:
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

def readfile(infile, defaultval=""):
  if os.path.exists(infile):
    with open(infile, 'r') as stream:
        return stream.read()[:-1]
  else:
    return defaultval

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

def colourise(display, nformat, green, yellow, red, withcomma, compare=None, addSign=False):
  global COLOUR

  cnum = format(display, ",d") if withcomma else display
  if addSign and display > 0:
    cnum = "+%s" % cnum
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

def getIRQ(storage, filter, sysinfo):
  storage[2] = storage[1]

  nproc = sysinfo["nproc"]
  irq = 0
  for line in grep(":", readfile("/proc/interrupts")).split("\n"):
    fields = line.split(" ")
    if fields[0] == "FIQ:":
      continue
    if fields[0] == "Err:":
      break
    for n in range(1, nproc + 1):
      irq += int(fields[n])

  storage[1] = (time.time(), irq)

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

def getDefaultInterface():
  interfaces = grep("^[ ]*.*:", readfile("/proc/net/dev"))
  for interface in [i for i in interfaces.split("\n")]:
    name = interface.split(":")[0]
    if name.startswith("eth") or name.startswith("enxb827eb"):
      return name

  return "wlan0"

# Collect processor stats once per loop, so that consistent stats are
# used when calculating total system load and individual core loads
def getProcStats(storage, filter):
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
def getCPULoad(storage, filter, proc, sysinfo):
  if proc[2][0] != 0:
    dTime = proc[0][0]
    core = proc[0][1]["cpu"]
    nproc = sysinfo["nproc"]
    c = []
    for i in range(0, 10):
      c.append(minmax(0, 100, (core[i] / nproc)))
    storage[0] = (dTime, [c[0], c[1], c[2], c[3], c[4], c[5], c[6], 100 - c[3]])

# Simple View of Total system load (combines hardware interrupts, software interrupts, and I/O waits into sys; removes idle)
def getSimpleCPULoad(storage, filter, proc, sysinfo):
  if proc[2][0] != 0:
    dTime = proc[0][0]
    core = proc[0][1]["cpu"]
    nproc = sysinfo["nproc"]
    c = []
    for i in range(0, 10):
      c.append(minmax(0, 100, (core[i] / nproc)))
    storage[0] = (dTime, [c[0], c[1], c[2] + c[4] + c[5] + c[6], 100 - c[3]])

# Individual core loads
def getCoreStats(storage, filter, proc):
  if "CPU" in filter:
    if proc[2][0] != 0:
      dTime = proc[0][0]
      load = []
      for core in sorted(proc[0][1]):
        if core == "cpu": continue
        load.append((core, 100 - minmax(0, 100, proc[0][1][core][3])))
      storage[0] = (dTime, load)

def getNetwork(storage, filter, interface):
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

def getBCM283X(storage, filter, STATS_WITH_VOLTS, STATS_WITH_PMIC_TEMP):
  global TCMAX, LIMIT_TEMP, TPMAX
  #Grab temp - ignore temps of 85C as this seems to be an occasional aberration in the reading
  
  if "TempCore" in filter:
    tCore = float(readfile("/sys/class/thermal/thermal_zone0/temp"))
    tCore = 0 if tCore < 0 else tCore
    if LIMIT_TEMP:
      TCMAX = tCore if (tCore > TCMAX and tCore < 85000) else TCMAX
    else:
      TCMAX = tCore if tCore > TCMAX else TCMAX
  else:
    tCore = None
    TCMAX = None

  if STATS_WITH_PMIC_TEMP and "TempPMIC" in filter:
    tPMIC = vcgencmd("measure_temp pmic", split=False)
    if tPMIC.find("error") != -1:
      tPMIC = None
      tPMIC_MAX = None
    else:
      tPMIC = float(tPMIC.split("=")[1].replace("'C",""))
      TPMAX = tPMIC if tPMIC > TPMAX else TPMAX
  else:
    tPMIC = None
    tPMIC_MAX = None

  if STATS_WITH_VOLTS and "Vcore" in filter:
    volts = vcgencmd("measure_volts core")
    if volts and (len(volts) - volts.find(".")) < 5:
      volts = "%s00" % volts[:-1]
    else:
      volts = volts[:-1]
  else:
    volts = ""

  farm = int(vcgencmd("measure_clock arm")) + 500000 if "ARM" in filter else 0
  fcore = int(vcgencmd("measure_clock core")) + 500000 if "Core" in filter else 0
  fh264 = int(vcgencmd("measure_clock h264")) + 500000 if "H264" in filter else 0
  fv3d = int(vcgencmd("measure_clock v3d")) + 500000 if "V3D" in filter else 0
  fisp = int(vcgencmd("measure_clock isp")) + 500000 if "ISP" in filter else 0

  storage[2] = storage[1]
  storage[1] = (time.time(),
                [farm,
                 fcore,
                 fh264,
                 fv3d,
                 fisp,
                 tCore, TCMAX,
                 tPMIC, TPMAX,
                 volts])

  if storage[2][0] != 0:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime
    storage[0] = (dTime, s1[1])

def getMemory(storage, filter, include_swap):
  MEMTOTAL = 0
  MEMFREE = 0
  MEMUSED = 0
  MEMDIFF = 0
  SWAPTOTAL = 0
  SWAPFREE = 0
  SWAPCACHED= 0

  for line in readfile("/proc/meminfo").split("\n"):
    field_groups = re.search("^(.*):[ ]*([0-9]*) .*$", line)
    if field_groups.group(1) in ["MemFree", "Buffers", "Cached", "SReclaimable"]:
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

def getGPUMem(storage, filter, STATS_GPU_R, STATS_GPU_M):
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

  storage[2] = storage[1]
  storage[1] = (time.time(), data)

  if storage[2][0] != 0:
    storage[0] = (storage[1][0] - storage[2][0], data)

def getMemDeltas(storage, filter, MEM, GPU):
  storage[2] = storage[1]
  storage[1] = (time.time(), MEM[1], GPU[1])

  if storage[2][0] == 0:
    storage[0] = (0, (0, 0, 0, 0))
  else:
    s1 = storage[1]
    s2 = storage[2]
    dTime = s1[0] - s2[0]
    dTime = 1 if dTime <= 0 else dTime
    dMem = s1[1][1][1] - s2[1][1][1]
    dGPU = s1[2][1]["reloc"][1] - s2[2][1]["reloc"][1]
    storage[0] = (dTime, (dMem, dGPU, storage[0][1][2] + dMem, storage[0][1][3] + dGPU))

def ceildiv(a, b):
  return -(-a // b)

def MHz(value, fwidth, cwidth):
  return ("%*dMHz" % (fwidth, value)).center(cwidth)

def MaxSDRAMVolts():
  vRAM = "1.2000V"
  for item in ["sdram_p", "sdram_c", "sdram_i"]:
    item_v = vcgencmd("measure_volts %s" % item)
    if item_v and (len(item_v) - item_v.find(".")) < 5:
      item_v = "%s00V" % item_v[:-1]
    vRAM = item_v if item_v and item_v > vRAM else vRAM
  return vRAM

# Calculate offset from voltage, allowing for 50mV of variance
def MaxSDRAMOffset():
  return (int(MaxSDRAMVolts()[:-1].replace(".", "")) - 12000 + 50) / 250

def getsysinfo(HARDWARE):

  sysinfo = {}

  RPI_MODEL = HARDWARE.GetPiModel() # RPi1, RPi2, RPi3 etc.

  VCG_INT = vcgencmd_items("get_config int", isInt=True)

  CORE_DEFAULT_IDLE = CORE_DEFAULT_BUSY = 250
  H264_DEFAULT_IDLE = H264_DEFAULT_BUSY = 250
  V3D_DEFAULT_IDLE = V3D_DEFAULT_BUSY = 250
  ISP_DEFAULT_IDLE = ISP_DEFAULT_BUSY = 250

  if VCG_INT.get("disable_auto_turbo", 0) == 0:
    CORE_DEFAULT_BUSY += 50
    H264_DEFAULT_BUSY += 50

  if RPI_MODEL == "RPi1":
    ARM_DEFAULT_IDLE = 700
    SDRAM_DEFAULT = 400
  elif RPI_MODEL == "RPi2":
    ARM_DEFAULT_IDLE = 600
    SDRAM_DEFAULT = 450
  elif RPI_MODEL == "RPi3":
    ARM_DEFAULT_IDLE = 600
    SDRAM_DEFAULT = 450
  elif RPI_MODEL == "RPi4":
    ARM_DEFAULT_IDLE = 600
    SDRAM_DEFAULT = 3200
  else:
    ARM_DEFAULT_IDLE = 600
    SDRAM_DEFAULT = 450

  sysinfo["hardware"]   = HARDWARE
  sysinfo["model"]      = RPI_MODEL
  sysinfo["nproc"]      = len(grep("^processor", readfile("/proc/cpuinfo")).split("\n"))

  # Kernel 4.8+ doesn't create cpufreq sysfs when force_turbo=1, in which case
  # min/max frequencies will both be the same as current
  if os.path.exists("/sys/devices/system/cpu/cpu0/cpufreq"):
    sysinfo["arm_min"] = int(int(readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"))/1000)
    sysinfo["arm_max"] = int(int(readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"))/1000)
  else:
    sysinfo["arm_min"] = int((int(vcgencmd("measure_clock arm")) + 500000) / 1e6)
    sysinfo["arm_max"] = sysinfo["arm_min"]

  if "sdram_freq" not in VCG_INT:
    VCG_INT["sdram_freq"] = int(int(vcgencmd("measure_clock pllh"))/1e6)

  sysinfo["core_max"]   = VCG_INT.get("core_freq", VCG_INT.get("gpu_freq", CORE_DEFAULT_BUSY))
  sysinfo["h264_max"]   = VCG_INT.get("h264_freq", VCG_INT.get("gpu_freq", H264_DEFAULT_BUSY))
  sysinfo["v3d_max"]   = VCG_INT.get("v3d_freq", VCG_INT.get("gpu_freq", V3D_DEFAULT_BUSY))
  sysinfo["isp_max"]   = VCG_INT.get("isp_freq", VCG_INT.get("gpu_freq", ISP_DEFAULT_BUSY))
  sysinfo["sdram_max"]  = VCG_INT.get("sdram_freq", SDRAM_DEFAULT)
  sysinfo["arm_volt"]   = VCG_INT.get("over_voltage", 0)
  sysinfo["sdram_volt"] = MaxSDRAMOffset()
  sysinfo["temp_limit"] = VCG_INT.get("temp_limit", 85)
  sysinfo["force_turbo"]= (VCG_INT.get("force_turbo", 0) != 0)

  if sysinfo["force_turbo"]:
    core_min = sysinfo["core_max"]
    h264_min = sysinfo["h264_max"]
    v3d_min = sysinfo["v3d_max"]
    isp_min = sysinfo["isp_max"]
  else:
    core_min = CORE_DEFAULT_IDLE
    h264_min = H264_DEFAULT_IDLE
    v3d_min = V3D_DEFAULT_IDLE
    isp_min = ISP_DEFAULT_IDLE
    core_min = sysinfo["core_max"] if sysinfo["core_max"] < core_min else core_min
    h264_min = sysinfo["h264_max"] if sysinfo["h264_max"] < h264_min else h264_min
    v3d_min = sysinfo["v3d_max"] if sysinfo["v3d_max"] < v3d_min else v3d_min
    isp_min = sysinfo["isp_max"] if sysinfo["isp_max"] < isp_min else isp_min

  sysinfo["core_min"] = core_min
  sysinfo["h264_min"] = h264_min
  sysinfo["v3d_min"] = v3d_min
  sysinfo["isp_min"] = isp_min

  # Calculate thresholds for green/yellow/red colour
  arm_min = sysinfo["arm_min"] - 10
  arm_max = sysinfo["arm_max"] - 5 if sysinfo["arm_max"] > ARM_DEFAULT_IDLE else 1e6

  core_min = sysinfo["core_min"] - 10
  core_max = sysinfo["core_max"] - 5 if sysinfo["core_max"] > CORE_DEFAULT_IDLE else 1e6

  h264_min = sysinfo["h264_min"] - 10
  h264_max = sysinfo["h264_max"] - 5 if sysinfo["h264_max"] > H264_DEFAULT_IDLE else 1e6

  v3d_min = sysinfo["v3d_min"] - 10
  v3d_max = sysinfo["v3d_max"] - 5 if sysinfo["v3d_max"] > V3D_DEFAULT_IDLE else 1e6

  isp_min = sysinfo["isp_min"] - 10
  isp_max = sysinfo["isp_max"] - 5 if sysinfo["isp_max"] > ISP_DEFAULT_IDLE else 1e6

  limits = {}
  limits["arm"] = (arm_min, arm_max)
  limits["core"] = (core_min, core_max)
  limits["h264"] = (h264_min, h264_max)
  limits["v3d"] = (v3d_min, v3d_max)
  limits["isp"] = (isp_min, isp_max)
  sysinfo["limits"] = limits

  return sysinfo

def ShowConfig(nice_value, priority_desc, sysinfo, args):
  global VCGENCMD, VERSION

  BOOTED = datetime.datetime.fromtimestamp(int(grep("btime", readfile("/proc/stat"), 1))).strftime('%c')

  MEM_ARM = int(vcgencmd("get_mem arm")[:-1])
  MEM_GPU = int(vcgencmd("get_mem gpu")[:-1])
  MEM_MAX = MEM_ARM + MEM_GPU

  SWAP_TOTAL = int(grep("SwapTotal", readfile("/proc/meminfo"), field=1, defaultvalue="0"))

  VCG_INT    = vcgencmd_items("get_config int", isInt=False)

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
  vRAM       = MaxSDRAMVolts()

  GOV        = readfile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "undefined")

  FIRMWARE   = ", ".join(grepv("Copyright", vcgencmd("version", split=False)).replace(", ","").split("\n")).replace(" ,",",")

  OTHER_VARS = ["temp_limit=%d" % TEMP_LIMIT]
  for item in ["force_turbo", "initial_turbo", "disable_auto_turbo", "avoid_pwm_pll",
               "hdmi_force_hotplug", "hdmi_force_edid_audio", "no_hdmi_resample",
               "disable_pvt", "sdram_schmoo"]:
    if item in VCG_INT:
      OTHER_VARS.append("%s=%s" % (item, VCG_INT[item]))

  CODECS = []
  for codec in ["H264", "H263", "WVC1", "MPG4", "MPG2", "VP8", "VP6", "VORB", "THRA", "MJPG", "FLAC", "PCM"]:
    if vcgencmd("codec_enabled %s" % codec) == "enabled":
      CODECS.append(codec)
  CODECS = CODECS if CODECS else ["none"]

  nv = "%s%d" % ("+" if nice_value > 0 else "", nice_value)

  SWAP_MEM = "" if SWAP_TOTAL == 0 else " plus %dMB Swap" % int(ceildiv(SWAP_TOTAL, 1024))
  ARM_ARCH = grep("^model name", readfile("/proc/cpuinfo"), field=2, head=1)[0:5]
  print("  Config: v%s, args \"%s\", priority %s (%s)" % (VERSION, " ".join(args), priority_desc, nv))
  print("   Board: %d x %s core%s available, %s governor (%s)" %  (NPROC, ARM_ARCH, "s"[NPROC==1:], GOV, sysinfo["hardware"]))
  print("  Memory: %sMB (split %sMB ARM, %sMB GPU)%s" % (MEM_MAX, MEM_ARM, MEM_GPU, SWAP_MEM))
  print("HW Block: | %s | %s | %s | %s |" % ("ARM".center(7), "Core".center(6), "H264".center(6), "SDRAM".center(11)))
  print("Min Freq: | %s | %s | %s | %s |" % (MHz(ARM_MIN,4,7), MHz(CORE_MIN,3,6), MHz(0,3,6),        MHz(SDRAM_MAX,3,11)))
  print("Max Freq: | %s | %s | %s | %s |" % (MHz(ARM_MAX,4,7), MHz(CORE_MAX,3,6), MHz(H264_MAX,3,6), MHz(SDRAM_MAX,3,11)))

  if vCore and (len(vCore) - vCore.find(".")) < 5:
    vCore = "%s00V" % vCore[:-1]

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

def addHeadingValue(filter, name, value, var1, var2, padding=' '):
  if name in filter:
    return ("%s%s%s" % (var1, padding, value), "%s%s%s" % (var2, padding, "="*len(value)))
  else:
    return (var1, var2)

def addDetailValue(filter, name, value, var1, padding=' ', prefix='', suffix=''):
  if name in filter:
    return "%s%s%s%s%s" % (var1, padding, prefix, value, suffix)
  else:
    return var1

def ShowHeadings(filter, display_flags, sysinfo):
  HDR1 = "Time    "
  HDR2 = "========"

  if display_flags["threshold"]:
    (HDR1, HDR2) = addHeadingValue(filter, "UFT", "UFT", HDR1, HDR2)

  if display_flags["core_volts"]:
    (HDR1, HDR2) = addHeadingValue(filter, "Vcore", "Vcore ", HDR1, HDR2)

  (HDR1, HDR2) = addHeadingValue(filter, "ARM",              "    ARM", HDR1, HDR2)
  (HDR1, HDR2) = addHeadingValue(filter, "Core",             "   Core", HDR1, HDR2)
  (HDR1, HDR2) = addHeadingValue(filter, "H264",             "   H264", HDR1, HDR2)
  (HDR1, HDR2) = addHeadingValue(filter, "V3D",              "    V3D", HDR1, HDR2)
  (HDR1, HDR2) = addHeadingValue(filter, "ISP",              "    ISP", HDR1, HDR2)
  (HDR1, HDR2) = addHeadingValue(filter, "TempCore", "Core Temp (Max)", HDR1, HDR2)

  if display_flags["temp_pmic"]:
    (HDR1, HDR2) = addHeadingValue(filter, "TempPMIC", "PMIC Temp (Max)", HDR1, HDR2)

  (HDR1, HDR2) = addHeadingValue(filter, "IRQ", " IRQ/s", HDR1, HDR2)

  if display_flags["network"]:
    if display_flags["human_readable"]:
      (HDR1, HDR2) = addHeadingValue(filter, "RX", "RX kB/s", HDR1, HDR2)
      (HDR1, HDR2) = addHeadingValue(filter, "TX", "TX kB/s", HDR1, HDR2)
    else:
      (HDR1, HDR2) = addHeadingValue(filter, "RX", "     RX B/s", HDR1, HDR2)
      (HDR1, HDR2) = addHeadingValue(filter, "TX", "     TX B/s", HDR1, HDR2)

  if display_flags["utilisation"]:
    (HDR1, HDR2) = addHeadingValue(filter, "CPUuser",  " %user", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUnice",  " %nice", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUsys",   "  %sys", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUidle",  " %idle", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUiowt",  " %iowt", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUirq",   "  %irq", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUs/irq", "%s/irq", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUtotal", "%total", HDR1, HDR2)

  if display_flags["sutilisation"]:
    (HDR1, HDR2) = addHeadingValue(filter, "CPUuser",  " %user", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUnice",  " %nice", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUsys",   " %sys+", HDR1, HDR2)
    (HDR1, HDR2) = addHeadingValue(filter, "CPUtotal", "%total", HDR1, HDR2)

  if display_flags["cpu_cores"]:
    for i in range(0, sysinfo["nproc"]):
      (HDR1, HDR2) = addHeadingValue(filter, "CPU", "  cpu%d" % i, HDR1, HDR2)

  if display_flags["gpu_malloc"]:
    (HDR1, HDR2) = addHeadingValue(filter, "GPUfree", "Malloc Free", HDR1, HDR2)

  if display_flags["gpu_reloc"]:
    if display_flags["gpu_malloc"]:
      (HDR1, HDR2) = addHeadingValue(filter, "GPUfree", "Reloc  Free", HDR1, HDR2)
    else:
      (HDR1, HDR2) = addHeadingValue(filter, "GPUfree", "GPUMem Free", HDR1, HDR2)

  if display_flags["cpu_mem"]:
    if display_flags["human_readable"]:
      (HDR1, HDR2) = addHeadingValue(filter, "MEMfree", "MemFreeMB / %used", HDR1, HDR2)
    else:
      (HDR1, HDR2) = addHeadingValue(filter, "MEMfree", "MemFreeKB / %used", HDR1, HDR2)
    if display_flags["swap"]:
      (HDR1, HDR2) = addHeadingValue(filter, "MEMfree", "(SwUse)", HDR1, HDR2, padding='')

  if display_flags["deltas"]:
    (HDR1, HDR2) = addHeadingValue(filter, "MEMdelta", "Delta  GPU B     Mem kB", HDR1, HDR2)

  if display_flags["accumulated"]:
    (HDR1, HDR2) = addHeadingValue(filter, "MEMaccum", "Accum  GPU B     Mem kB", HDR1, HDR2)

  printn("%s\n%s" % (HDR1, HDR2))

def ShowStats(filter, display_flags, sysinfo, threshold, bcm2385, irq, network, cpuload, memory, gpumem, cores, deltas):
  global ARM_MIN, ARM_MAX

  now = datetime.datetime.now()
  TIME = "%02d:%02d:%02d" % (now.hour, now.minute, now.second)

  LINE = "%s" % TIME

  if display_flags["threshold"] and "UFT" in filter:
    (volts_now, volts_hist) = threshold["under-voltage"]
    (freq_now, freq_hist)   = threshold["arm-capped"]
    (throt_now, throt_hist) = threshold["throttled"]

    dVolts = dFreq = dThrottled = " "
    nVolts = nFreq = nThrottled = 0

    if volts_now == 1:
      dVolts = "U"
      nVolts = 3
    elif volts_hist == 1:
      dVolts = "u"
      nVolts = 2

    if freq_now == 1:
      dFreq = "F"
      nFreq = 3
    elif freq_hist == 1:
      dFreq = "f"
      nFreq = 2

    if throt_now == 1:
      dThrottled = "T"
      nThrottled = 3
    elif throt_hist == 1:
      dThrottled = "t"
      nThrottled = 2

    uft = "%s%s%s" % (colourise(dVolts,     "%s", 1, 2, 3, False, compare=nVolts),
                      colourise(dFreq,      "%s", 1, 2, 3, False, compare=nFreq),
                      colourise(dThrottled, "%s", 1, 2, 3, False, compare=nThrottled))

    LINE = addDetailValue(filter, "UFT", uft, LINE)

  limits = sysinfo["limits"]
  (arm_min, arm_max) = limits["arm"]
  (core_min, core_max) = limits["core"]
  (h264_min, h264_max) = limits["h264"]
  (v3d_min, v3d_max) = limits["v3d"]
  (isp_min, isp_max) = limits["isp"]

  fTC = "%5.2fC" if bcm2385[3] < 100000 else "%5.1fC"
  fTM = "%5.2fC" if bcm2385[4] < 100000 else "%5.1fC"

  if display_flags["core_volts"]:
    LINE = addDetailValue(filter, "Vcore", bcm2385[9], LINE)

  LINE = addDetailValue(filter, "ARM",  colourise(bcm2385[0]/1000000, "%4dMhz", arm_min,     None,  arm_max, False), LINE)
  LINE = addDetailValue(filter, "Core", colourise(bcm2385[1]/1000000, "%4dMhz",core_min,     None, core_max, False), LINE)
  LINE = addDetailValue(filter, "H264", colourise(bcm2385[2]/1000000, "%4dMhz",       0, h264_min, h264_max, False), LINE)
  LINE = addDetailValue(filter, "V3D",  colourise(bcm2385[3]/1000000, "%4dMhz",       0,  v3d_min,  v3d_max, False), LINE)
  LINE = addDetailValue(filter, "ISP",  colourise(bcm2385[4]/1000000, "%4dMhz",       0,  isp_min,  isp_max, False), LINE)

  if "TempCore" in filter:
    LINE = addDetailValue(filter, "TempCore", colourise(bcm2385[5]/1000,    fTC,         50.0,     70.0,     80.0, False), LINE)
    LINE = addDetailValue(filter, "TempCore", colourise(bcm2385[6]/1000,    fTM,         50.0,     70.0,     80.0, False), LINE, prefix='(', suffix=')')

  if display_flags["temp_pmic"] and "TempPMIC" in filter:
    fTC = "%5.2fC" if bcm2385[7] < 100000 else "%5.1fC"
    fTM = "%5.2fC" if bcm2385[8] < 100000 else "%5.1fC"
    LINE = addDetailValue(filter, "TempPMIC", colourise(bcm2385[7], fTC, 50.0, 70.0, 80.0, False), LINE)
    LINE = addDetailValue(filter, "TempPMIC", colourise(bcm2385[8], fTM, 50.0, 70.0, 80.0, False), LINE, prefix='(', suffix=')')

  LINE = addDetailValue(filter, "IRQ", colourise(irq[0], "%6s", 500, 2500, 5000, True), LINE)

  if display_flags["network"]:
    if display_flags["human_readable"]:
      LINE = addDetailValue(filter, "RX", colourise(int(network[0]/1024), "%7s", 0.5e3, 2.5e3, 5.0e3, True), LINE)
      LINE = addDetailValue(filter, "TX", colourise(int(network[1]/1024), "%7s", 0.5e3, 2.5e3, 5.0e3, True), LINE)
    else:
      LINE = addDetailValue(filter, "RX", colourise(network[0],     "%11s", 0.5e6, 2.5e6, 5.0e6, True), LINE)
      LINE = addDetailValue(filter, "TX", colourise(network[1],     "%11s", 0.5e6, 2.5e6, 5.0e6, True), LINE)

  if display_flags["utilisation"]:
    LINE = addDetailValue(filter, "CPUuser",  colourise(cpuload[0], "%6.2f",  30, 50, 70, False), LINE)
    LINE = addDetailValue(filter, "CPUnice",  colourise(cpuload[1], "%6.2f",  10, 20, 30, False), LINE)
    LINE = addDetailValue(filter, "CPUsys",   colourise(cpuload[2], "%6.2f",  30, 50, 70, False), LINE)
    LINE = addDetailValue(filter, "CPUidle",  colourise(cpuload[3], "%6.2f",  70, 50, 30, False), LINE)
    LINE = addDetailValue(filter, "CPUiowt",  colourise(cpuload[4], "%6.2f",   2,  5, 10, False), LINE)
    LINE = addDetailValue(filter, "CPUirq",   colourise(cpuload[5], "%6.2f",   2,  5, 10, False), LINE)
    LINE = addDetailValue(filter, "CPUs/irq", colourise(cpuload[6], "%6.2f", 7.5, 15, 20, False), LINE)
    LINE = addDetailValue(filter, "CPUtotal", colourise(cpuload[7], "%6.2f",  30, 50, 70, False), LINE)

  if display_flags["sutilisation"]:
    LINE = addDetailValue(filter, "CPUuser",  colourise(cpuload[0], "%6.2f",  30, 50, 70, False), LINE)
    LINE = addDetailValue(filter, "CPUnice",  colourise(cpuload[1], "%6.2f",  10, 20, 30, False), LINE)
    LINE = addDetailValue(filter, "CPUsys",   colourise(cpuload[2], "%6.2f",  30, 50, 70, False), LINE)
    LINE = addDetailValue(filter, "CPUtotal", colourise(cpuload[3], "%6.2f",  30, 50, 70, False), LINE)

  if display_flags["cpu_cores"] and "CPU" in filter:
    for core in cores:
      LINE = addDetailValue(filter, "CPU", colourise(core[1], "%6.2f", 30, 50, 70, False), LINE)

  if display_flags["gpu_malloc"]:
    data = gpumem["malloc"]
    LINE = addDetailValue(filter, "GPUfree", colourise(data[0],   "%4s", 70, 50, 30, False, compare=data[2]), LINE)
    LINE = addDetailValue(filter, "GPUfree", colourise(data[2], "%3d%%", 70, 50, 30, False, compare=data[2]), LINE, prefix='(', suffix=')')

  if display_flags["gpu_reloc"]:
    data = gpumem["reloc"]
    LINE = addDetailValue(filter, "GPUfree", colourise(data[0],   "%4s", 70, 50, 30, False, compare=data[2]), LINE)
    LINE = addDetailValue(filter, "GPUfree", colourise(data[2], "%3d%%", 70, 50, 30, False, compare=data[2]), LINE, prefix='(', suffix=')')

  if display_flags["cpu_mem"]:

    if display_flags["human_readable"]:
      data = "%s / %s" % (colourise(int(memory[1]/1024),     "%9s", 60, 75, 85, True,  compare=memory[2]),
                          colourise(memory[2],           "%4.1f%%", 60, 75, 85, False, compare=memory[2]))
    else :
      data = "%s / %s" % (colourise(memory[1],      "%9s", 60, 75, 85, True,  compare=memory[2]),
                          colourise(memory[2],  "%4.1f%%", 60, 75, 85, False, compare=memory[2]))
    LINE = addDetailValue(filter, "MEMfree", data, LINE)

    # Swap memory
    if display_flags["swap"] and memory[4] is not None:
      LINE = addDetailValue(filter, "MEMfree", colourise(memory[4], "%4.1f%%", 1, 5, 15, False, compare=memory[4]), LINE, padding='', prefix='(', suffix=')')

  if display_flags["deltas"] and "MEMdelta" in filter:
    dmem = deltas[0]
    dgpu = deltas[1]

    if  dmem < 0:
      cmem = 2
    elif dmem > 0:
      cmem = 1
    else:
      cmem = 0

    if  dgpu < 0:
      cgpu = 2
    elif dgpu > 0:
      cgpu = 1
    else:
      cgpu = 0

    LINE = addDetailValue(filter, "MEMdelta", colourise(dgpu, "%12s",  1, None, 2, True, compare=cgpu, addSign=True), LINE)
    LINE = addDetailValue(filter, "MEMdelta", colourise(dmem, "%10s",  1, None, 2, True, compare=cmem, addSign=True), LINE)

  if display_flags["accumulated"] and "MEMaccum" in filter:
    dmem = deltas[2]
    dgpu = deltas[3]

    if  dmem < 0:
      cmem = 2
    elif dmem > 0:
      cmem = 1
    else:
      cmem = 0

    if  dgpu < 0:
      cgpu = 2
    elif dgpu > 0:
      cgpu = 1
    else:
      cgpu = 0

    LINE = addDetailValue(filter, "MEMaccum", colourise(dgpu, "%12s",  1, None, 2, True, compare=cgpu, addSign=True), LINE)
    LINE = addDetailValue(filter, "MEMaccum", colourise(dmem, "%10s",  1, None, 2, True, compare=cmem, addSign=True), LINE)

  printn("\n%s" % LINE)

def ShowHelp():
  print("Usage: %s [c|m] [d#] [H#] [i <iface>] [k] [L|N|M] [o[-+]col,...] [y|Y] [x|X|r|R] [p|P] [T] [t] [g|G] [f|F] [D][A] [s|S] [q|Q] [V|U|W|C] [Z] [h]" % os.path.basename(__file__))
  print()
  print("c        Colourise output (white: minimal load or usage, then ascending through green, amber and red).")
  print("m        Monochrome output (no colourise)")
  print("d #      Specify interval (in seconds) between each iteration - default is 2")
  print("H #      Header every n iterations (0 = no header, default is 30)")
  print("J #      Exit after n iterations (0 = no auto exit (default))")
  print("i iface  Monitor network interface other than the default eth0/enx<MAC> or wlan0, eg. br1")
  print("k        Show RX/TX and Memory stats in human-friendly units (kB and MB respectively)")
  print("L        Run at lowest priority (nice +20) - default")
  print("N        Run at normal priority (nice 0)")
  print("M        Run at maximum priority (nice -20)")
  print("o cols   Comma delimited list of columns to display. Prefix column name with - to hide a column, and + to add a column. Use no prefix to replace all default columns. Column names are case-sensitive.")
  print("         eg. \"-o-RX,-TX\" to hide both RX and TX, while continuing to show all other default columns.")
  print("         eg. \"-o+V3D,+ISP,-H264\" to show V3D and ISP columns, hide H264, and continue to show all other default columns.")
  print("         eg. \"-oRX,TX\" to show only RX and TX (ignore other -col/+col definitions, and disable default columns).")
  print("         Available columns: %s" % ", ".join(DEFAULT_COLS_FILTER + EXTRA_COLS_FILTER))
  print("y/Y      Do (y)/don't (Y) show threshold event flags (U=under-voltage, F=ARM freq capped, T=currently throttled, lowercase if event has occurred in the past")
  print("r/R      Do (r)/don't (R) monitor simple CPU load and memory usage stats (not compatible with x/X)")
  print("x/X      Do (x)/don't (X) monitor detailed CPU load and memory usage stats (not compatible with r/R)")
  print("p/P      Do (p)/don't (P) monitor individual core load stats (when core count > 1)")
  print("g/G      Do (g)/don't (G) monitor additional GPU memory stats (reloc memory)")
  print("f/F      Do (f)/don't (F) monitor additional GPU memory stats (malloc memory)")
  print("s/S      Do (s)/don't (S) include any available swap memory when calculating memory statistics")
  print("q/Q      Do (q)/don't (Q) suppress configuraton information")
  print("e/E      Do (e)/don't (E) show core voltage")
  print("D        Show delta memory - negative: memory allocated, positive: memory freed")
  print("A        Show accumulated delta memory - negative: memory allocated, positive: memory freed")
  print("T        Maximum temperature is normally capped at 85C - use this option to disable temperature cap")
  print("t        Show PMIC temperature (if available, ignore if not)")
  print()
  print("V        Check version")
  print("U        Update to latest version if an update is available")
  print("W        Force update to latest version")
  print("C        Disable auto-update")
  print()
  print("Z        Ignore any default configuration")
  print()
  print("h        Print this help")
  print()
  print("Set default properties in ~/.bcmstat.conf or ~/.config/bcmstat.conf")
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
  global GITHUB

  return get_latest_version_ex("%s/%s" % (GITHUB, "VERSION"))

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
  global COLOUR, SUDO, LIMIT_TEMP
  global PEAKVALUES
  global VCGENCMD_GET_MEM

  HARDWARE = RPIHardware()

  INTERFACE = getDefaultInterface()

  DELAY = 2
  HDREVERY = 30
  QEVERY = 0

  COLOUR = True
  QUIET = False
  NICE_ADJUST = +20
  INCLUDE_SWAP = True
  COLUMN_FILTER = list(DEFAULT_COLS_FILTER)

  STATS_THRESHOLD = False
  STATS_THRESHOLD_CLEAR = False
  STATS_WITH_VOLTS = False
  STATS_WITH_PMIC_TEMP = False
  STATS_CPU_MEM = False
  STATS_UTILISATION = False
  SIMPLE_UTILISATION = False
  STATS_CPU_CORE= False
  STATS_GPU_R = False
  STATS_GPU_M = False

  STATS_DELTAS = False
  STATS_ACCUMULATED = False

  HUMAN_READABLE = False

  CHECK_UPDATE = True

  IGNORE_DEFAULTS = False

  # Pre-process command line args to determine if we should
  # ignored the stored defaults
  VALUE = False
  for x in " ".join(args):
    if x == " ":
      VALUE = False
      continue

    if not (VALUE or (x >= "0" and x <= "9")):
      if x == "Z":
        IGNORE_DEFAULTS = True
        break
      VALUE = x in ["i", "d", "h"]

  oargs = args

  # Read default settings from config file
  # Can be overidden by command line.
  if IGNORE_DEFAULTS == False:
    config1 = os.path.expanduser("~/.bcmstat.conf")
    config2 = os.path.expanduser("~/.config/bcmstat.conf")
    if os.path.exists(config1):
      args.insert(0, readfile(config1))
    elif os.path.exists(config2):
      args.insert(0, readfile(config2))

  # Crude attempt at argument parsing as I don't want to use argparse
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
      VALUE = x in ["i", "o", "d", "h"]
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
    elif a1 == "J":
      QEVERY = int(a2)

    elif a1 == "i":
      INTERFACE = a2

    elif a1 == "o":
      newCols = []
      invalidCols = []
      ALL_COLS = DEFAULT_COLS_FILTER + EXTRA_COLS_FILTER
      for column in a2.split(","):
        if column:
          if column.startswith("-"):
            colname = column[1:]
            if colname in COLUMN_FILTER:
              COLUMN_FILTER.remove(colname)
          elif column.startswith("+"):
            colname = column[1:]
            if colname not in COLUMN_FILTER:
              COLUMN_FILTER.append(colname)
          else:
            colname = column
            newCols.append(column)

          if colname and colname not in ALL_COLS:
            invalidCols.append(colname)

      if invalidCols:
        print("Unknown column(s) specified: %s" % ", ".join(sorted(set(invalidCols))))
        sys.exit(2)

      if newCols:
        COLUMN_FILTER = newCols

    elif a1 == "L":
      NICE_ADJUST = +20
    elif a1 == "N":
      NICE_ADJUST = 0
    elif a1 == "M":
      NICE_ADJUST = -20

    elif a1 == "e":
      STATS_WITH_VOLTS = True
    elif a1 == "E":
      STATS_WITH_VOLTS = False

    elif a1 == "g":
      STATS_GPU_R = True
    elif a1 == "G":
      STATS_GPU_R = False

    elif a1 == "f":
      STATS_GPU_M = True
    elif a1 == "F":
      STATS_GPU_M = False

    elif a1 == "y":
      STATS_THRESHOLD = True
    elif a1 == "Y":
      STATS_THRESHOLD = False

    elif a1 == "r":
      STATS_CPU_MEM = True
      SIMPLE_UTILISATION = True
      STATS_UTILISATION = False
    elif a1 == "R":
      STATS_CPU_MEM = False
      SIMPLE_UTILISATION = False

    elif a1 == "x":
      STATS_CPU_MEM = True
      SIMPLE_UTILISATION = False
      STATS_UTILISATION = True
    elif a1 == "X":
      STATS_CPU_MEM = False
      STATS_UTILISATION = False

    elif a1 == "p":
      STATS_CPU_CORE = True
    elif a1 == "P":
      STATS_CPU_CORE = False

    elif a1 == "T":
      LIMIT_TEMP = False

    elif a1 == "t":
      STATS_WITH_PMIC_TEMP = True

    elif a1 == "D":
      STATS_DELTAS = True

    elif a1 == "A":
      STATS_ACCUMULATED = True

    elif a1 == "k":
      HUMAN_READABLE = True

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

    elif a1 in ["-", "Z"]:
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

  commands = vcgencmd("commands")[1:-1].split(", ")

  if STATS_THRESHOLD:
    if "get_throttled" in commands:
      if vcgencmd("get_throttled 0x0").find("error_msg") == -1:
        STATS_THRESHOLD_CLEAR = True
    else:
      print("WARNING: Threshold query not supported by current firmware - option will be disabled")
      STATS_THRESHOLD = False

  # Collect basic system configuration
  sysinfo = getsysinfo(HARDWARE)
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
  UFT = [(0, None), (0, None), (0, None)]
  DELTAS=[(0, None), (0, None), (0, None)]

  if STATS_THRESHOLD:
    HARDWARE.GetThresholdValues(UFT, COLUMN_FILTER, STATS_THRESHOLD_CLEAR)

  getBCM283X(BCM, COLUMN_FILTER, STATS_WITH_VOLTS, STATS_WITH_PMIC_TEMP)
  if BCM[1][1][7] == None:
    STATS_WITH_PMIC_TEMP = False

  getIRQ(IRQ, COLUMN_FILTER, sysinfo)

  getNetwork(NET, COLUMN_FILTER, INTERFACE)

  STATS_NETWORK = (NET[1][1] != "")

  if STATS_DELTAS or STATS_ACCUMULATED:
    STATS_CPU_MEM = True
    STATS_GPU_R = True

  if STATS_CPU_CORE or STATS_UTILISATION or SIMPLE_UTILISATION:
    getProcStats(PROC, COLUMN_FILTER)

  if STATS_CPU_MEM:
    getMemory(MEM, COLUMN_FILTER, (SWAP_ENABLED and INCLUDE_SWAP))

  if STATS_GPU_R or STATS_GPU_M:
    getGPUMem(GPU, COLUMN_FILTER, STATS_GPU_R, STATS_GPU_M)

  if STATS_DELTAS or STATS_ACCUMULATED:
    getMemDeltas(DELTAS, COLUMN_FILTER, MEM, GPU)

  count = HDREVERY
  tcount = 0
  firsthdr = True

  display_flags = {"threshold":   STATS_THRESHOLD,
                   "network":     STATS_NETWORK,
                   "cpu_mem":     STATS_CPU_MEM,
                   "core_volts":  STATS_WITH_VOLTS,
                   "human_readable": HUMAN_READABLE,
                   "utilisation": STATS_UTILISATION,
                   "sutilisation": SIMPLE_UTILISATION,
                   "cpu_cores":   STATS_CPU_CORE,
                   "gpu_reloc":   STATS_GPU_R,
                   "gpu_malloc":  STATS_GPU_M,
                   "swap":        (SWAP_ENABLED and INCLUDE_SWAP),
                   "deltas":      STATS_DELTAS,
                   "accumulated": STATS_ACCUMULATED,
                   "temp_pmic":   STATS_WITH_PMIC_TEMP}

  #Store peak values
  PEAKVALUES = {"01#IRQ":0, "02#RX":0, "03#TX":0}
  if STATS_THRESHOLD:
    PEAKVALUES.update({"04#UVOLT":0, "05#FCAPPED":0, "06#THROTTLE":0})

  while [ True ]:
    if HDREVERY != 0 and count >= HDREVERY:
      if not QUIET or not firsthdr: printn("\n\n")
      ShowHeadings(COLUMN_FILTER, display_flags, sysinfo)
      firsthdr = False
      count = 0
    count += 1
    tcount += 1

    if STATS_THRESHOLD:
      HARDWARE.GetThresholdValues(UFT, COLUMN_FILTER, STATS_THRESHOLD_CLEAR)

    getBCM283X(BCM, COLUMN_FILTER, STATS_WITH_VOLTS, STATS_WITH_PMIC_TEMP)

    getIRQ(IRQ, COLUMN_FILTER, sysinfo)

    if STATS_NETWORK:
      getNetwork(NET, COLUMN_FILTER, INTERFACE)

    if STATS_CPU_CORE or STATS_UTILISATION or SIMPLE_UTILISATION:
      getProcStats(PROC, COLUMN_FILTER)

    if STATS_CPU_CORE:
      getCoreStats(CORE, COLUMN_FILTER, PROC)

    if STATS_UTILISATION:
      getCPULoad(CPU, COLUMN_FILTER, PROC, sysinfo)

    if SIMPLE_UTILISATION:
      getSimpleCPULoad(CPU, COLUMN_FILTER, PROC, sysinfo)

    if STATS_CPU_MEM:
      getMemory(MEM, COLUMN_FILTER, (SWAP_ENABLED and INCLUDE_SWAP))

    if STATS_GPU_R or STATS_GPU_M:
      getGPUMem(GPU, COLUMN_FILTER, STATS_GPU_R, STATS_GPU_M)

    if STATS_DELTAS or STATS_ACCUMULATED:
      getMemDeltas(DELTAS, COLUMN_FILTER, MEM, GPU)

    ShowStats(COLUMN_FILTER, display_flags, sysinfo, UFT[0][1], BCM[0][1], IRQ[0][1], NET[0][1], CPU[0][1], MEM[0][1], GPU[0][1], CORE[0][1], DELTAS[0][1])

    n = {}
    n["01#IRQ"] = IRQ[0][1][0] if IRQ[0][1][0] > PEAKVALUES["01#IRQ"] else PEAKVALUES["01#IRQ"]

    if STATS_NETWORK:
      n["02#RX"]  = NET[0][1][0] if NET[0][1][0] > PEAKVALUES["02#RX"] else PEAKVALUES["02#RX"]
      n["03#TX"]  = NET[0][1][1] if NET[0][1][1] > PEAKVALUES["03#TX"] else PEAKVALUES["03#TX"]

    if STATS_THRESHOLD:
      n["04#UVOLT"]    = PEAKVALUES["04#UVOLT"] + UFT[0][1]["under-voltage"][0]
      n["05#FCAPPED"]  = PEAKVALUES["05#FCAPPED"] + UFT[0][1]["arm-capped"][0]
      n["06#THROTTLE"] = PEAKVALUES["06#THROTTLE"] + UFT[0][1]["throttled"][0]

    PEAKVALUES = n

    if QEVERY > 0 and tcount >= QEVERY:
      raise KeyboardInterrupt

    time.sleep(DELAY)

if __name__ == "__main__":
  try:
    PEAKVALUES = None
    main(sys.argv[1:])
  except (KeyboardInterrupt, SystemExit) as e:
    print()
    if PEAKVALUES:
      line = ""
      for item in sorted(PEAKVALUES): line = "%s%s%s: %s" % (line, (", " if line else ""), item[3:], PEAKVALUES[item])
      print("Peak Values: %s" % line)
    if type(e) == SystemExit: sys.exit(int(str(e)))
