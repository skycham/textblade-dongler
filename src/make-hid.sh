#!/bin/sh
MAC=$(echo "$1" | tr a-f A-F)
DEV=hci0
CTRL=$(tr a-f A-F </sys/class/bluetooth/$DEV/address)

function die() {
  echo "FATAL: $@" 1>&2
  exit 1
}

[ -z "$CTRL" ] || [ -z "$MAC" ] && die "Call as: $0 keyboard-mac"

infodir="/var/lib/bluetooth/$CTRL/$MAC"
[ -d "$infodir" ] || die "$infodir does not exist, cannot continue"

if ! bccmd psget 0x3cd > /dev/null; then
  die "Unfortunately, your dongle is not capable of HID mode (or not powered on)"
fi

function readKeys() {
  export Key= EDiv= Rand=
  export t= $(cat "/var/lib/bluetooth/$CTRL/$MAC/info" | sed -n -e '/^\[LongTermKey/,/^\[/p' | grep -E '^(Key|EDiv|Rand)=[A-F0-9]+$')
  if [ -z "$Key" ] || [ -z "$EDiv" ] || [ -z "$Rand" ]; then
    return 1
  fi
  return 0
}

function toHex() { echo "obase=16; $1" | bc; }
function revbytes(){ local b=""; for ((i=2;i<=${#1};i+=2)); do b=$b${1: -i:2}; done; echo $b; }
function rev16(){ local b=""; for ((i=0;i<${#1};i+=4)); do b=$b${1: i+2:2}${1: i:2}; done; echo $b; }
function pad() { local b=000000000000000000000000000000000000000000000000000000$1; echo ${b: -$2*2:$2*2}; }
function makeToken() { echo $(echo $MAC|tr -d : )1482$(rev16 $(pad $(toHex $EDiv) 2))$(revbytes $(pad $(toHex $Rand) 8))$(rev16 $(pad $Key 16)); }
function formatToken() { local b=""; for ((i=0;i<${#1};i+=4)); do b="$b${1: i:4} "; done; echo $b | tr A-Z a-z; }

readKeys || die "Could not extract pairing keys"
token=$(formatToken $(makeToken))
[ ${#token} -eq 84 ] || die "Token $token has incorrect length"

echo "Writing $token to /dev/$DEV"
bccmd psload -s 0 /dev/stdin <<-EOF
// PSKEY_USR42
&02b4 = $token
// PSKEY_INITIAL_BOOTMODE
&03cd = 0002
&04b0 = 03c0 03cc 22c0
&04b1 = 01f9 0042
&04b2 = 02bf 03c0 03cc 02bd 000d 000e 215f
&04b8 = 0000
&04b9 = 0000
&04ba = 0001
&04f8 = 0000
&04f9 = 0001
&0538 = 100b
&0539 = 0001
&053a = 0001
&053b = 0000 0000 0000
&053c = 0002
&053d = 0000
&053e = 0002 0001 000a 0008 0010 0008 0020 0008 0040 0004 0080 0002 0140 0001 0200 0002
EOF
if [ $? -ne 0 ]; then
  die 'write failed :-('
fi

bccmd psread | grep '&02b4'
echo "Make sure the above output is $token"
