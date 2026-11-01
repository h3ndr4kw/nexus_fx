#!/usr/bin/env bash
###############################################################################
# Script Name : fe_health_check.sh
# Purpose     : Agentless health check measurement script for Smart-E FE node
# Contract    : Tagged stdout output ##META, ##M, ##RAW, ##ERR, ##END
###############################################################################

# Ensure complete binary search PATH in non-login / non-interactive SSH shells
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Binary path discovery with safe fallbacks
TCPDUMP_BIN=$(which tcpdump 2>/dev/null || echo "/usr/sbin/tcpdump")
ARP_BIN=$(which arp 2>/dev/null || echo "/usr/sbin/arp")
TIMEOUT_BIN=$(which timeout 2>/dev/null || echo "/usr/bin/timeout")

# 1. METADATA & VERSION DISCOVERY
oam_version=""
# Priority 1: Read OAM_VERSION from /opt/opwv/ost/etc/vars (if present)
if [ -f /opt/opwv/ost/etc/vars ]; then
  oam_version=$(grep OAM_VERSION /opt/opwv/ost/etc/vars 2>/dev/null | cut -d "=" -f2 | tr -d ' \r\n')
fi

# Priority 2: Detect version directory under /opt/opwv/integra/<version>
if [ -z "$oam_version" ]; then
  integra_dir=$(ls -d /opt/opwv/integra/[0-9]* 2>/dev/null | head -1)
  if [ -n "$integra_dir" ]; then
    oam_version=$(basename "$integra_dir" | tr -d ' \r\n')
  fi
fi

# Priority 3: Detect version from /etc/init.d/oamsca-v* service script
if [ -z "$oam_version" ]; then
  sca_script=$(ls -d /etc/init.d/oamsca-v* 2>/dev/null | head -1)
  if [ -n "$sca_script" ]; then
    oam_version=$(basename "$sca_script" | sed 's/.*oamsca-v//' | tr -d ' \r\n')
  fi
fi

# Priority 4: Default fallback version for Smart-E clusters
if [ -z "$oam_version" ]; then
  oam_version="8.4"
fi

fe_host=$(hostname 2>/dev/null | tr -d '\r\n')
echo "##META|${fe_host}|${oam_version}"

# Resolve tool and configuration paths with automatic discovery fallbacks
SSL_FILE="/opt/opwv/integra/$oam_version/tools/trafficserver/etc/trafficserver/ssl_multicert.config"
if [ ! -f "$SSL_FILE" ]; then
  alt_ssl=$(find /opt/opwv/ -name "ssl_multicert.config" 2>/dev/null | head -1)
  [ -n "$alt_ssl" ] && [ -f "$alt_ssl" ] && SSL_FILE="$alt_ssl"
fi

VPPCTL="/opt/opwv/integra/$oam_version/tools/vpp/bin/vppctl"
if [ ! -x "$VPPCTL" ]; then
  alt_vpp=$(find /opt/opwv/ -name "vppctl" 2>/dev/null | head -1)
  [ -n "$alt_vpp" ] && [ -x "$alt_vpp" ] && VPPCTL="$alt_vpp"
fi

LOGDECODER="/opt/opwv/oam/$oam_version/tools/bin/LogDecoder.sh"
if [ ! -x "$LOGDECODER" ]; then
  alt_decoder=$(find /opt/opwv/ -name "LogDecoder.sh" 2>/dev/null | head -1)
  [ -n "$alt_decoder" ] && [ -x "$alt_decoder" ] && LOGDECODER="$alt_decoder"
fi

subscriber_ifc=veth1

# 2. DISK CHECK
# df -P /var /var/opt/opwv/logs
DISK_RAW=$(df -P /var /var/opt/opwv/logs 2>/dev/null | grep -E -v 'Filesystem|cccache|tmp|cores')
DISK_METRIC=""
if [ -n "$DISK_RAW" ]; then
  DISK_METRIC=$(echo "$DISK_RAW" | awk '{gsub(/%/,"",$5); print $6 "=" $5}' | tr '\n' ';' | sed 's/;$//')
fi
echo "##M|DISK|${DISK_METRIC}"
RAW_B64=$(printf "%s" "$DISK_RAW" | base64 | tr -d '\r\n')
echo "##RAW|DISK|${RAW_B64}"

# 3. INODE CHECK
INODE_RAW=$(df -Pi /var /var/opt/opwv/logs 2>/dev/null | grep -E -v 'Filesystem|cccache|tmp|cores')
INODE_METRIC=""
if [ -n "$INODE_RAW" ]; then
  INODE_METRIC=$(echo "$INODE_RAW" | awk '{gsub(/%/,"",$5); print $6 "=" $5}' | tr '\n' ';' | sed 's/;$//')
fi
echo "##M|INODE|${INODE_METRIC}"
RAW_B64=$(printf "%s" "$INODE_RAW" | base64 | tr -d '\r\n')
echo "##RAW|INODE|${RAW_B64}"

# 4. ATS CHECK
ATS_RAW=$(netstat -anop < /dev/null 2>/dev/null | grep -w 3128 | grep -i LISTEN | grep -i traffic_man)
ATS_COUNT=0
if [ -n "$ATS_RAW" ]; then
  ATS_COUNT=$(echo "$ATS_RAW" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
fi
echo "##M|ATS|${ATS_COUNT}"
RAW_B64=$(printf "%s" "$ATS_RAW" | base64 | tr -d '\r\n')
echo "##RAW|ATS|${RAW_B64}"

# 5. VPP CHECK
VPP_RAW=""
if [ -x "$VPPCTL" ]; then
  VPP_RAW=$($VPPCTL show ip neighbor < /dev/null 2>/dev/null | grep -i '192.168.8.1 ')
fi
ARP_RAW=$($ARP_BIN -n < /dev/null 2>/dev/null | grep -i '192.168.8.1 ')

MAC_VPP_0=$(echo "$VPP_RAW" | awk '/device_0\/4\/0/ {print $(NF-1)}' | head -1 | tr -d '\r\n')
MAC_VPP_1=$(echo "$VPP_RAW" | awk '/device_0\/5\/0/ {print $(NF-1)}' | head -1 | tr -d '\r\n')
MAC_ARP_0=$(echo "$ARP_RAW" | awk '/veth1/ {print $3}' | head -1 | tr -d '\r\n')
MAC_ARP_1=$(echo "$ARP_RAW" | awk '/veth2/ {print $3}' | head -1 | tr -d '\r\n')

echo "##M|VPP|${MAC_VPP_0}|${MAC_VPP_1}|${MAC_ARP_0}|${MAC_ARP_1}"
COMBINED_VPP="VPP_RAW:
$VPP_RAW
ARP_RAW:
$ARP_RAW"
RAW_B64=$(printf "%s" "$COMBINED_VPP" | base64 | tr -d '\r\n')
echo "##RAW|VPP|${RAW_B64}"

# 6. TCP CHECK
# Run tcpdump on subscriber_ifc (veth1). Capture up to 5 packets or timeout after 10s.
TCP_RAW=$($TIMEOUT_BIN 10 $TCPDUMP_BIN -nni "$subscriber_ifc" net 10.0.0.0/8 -c 5 < /dev/null 2>/dev/null)
TCP_COUNT=0
if [ -n "$TCP_RAW" ]; then
  TCP_COUNT=$(echo "$TCP_RAW" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
fi

# Fallback: if veth1 captured fewer than 5 packets, check veth2
if [ "$TCP_COUNT" -lt 5 ]; then
  TCP_RAW_ALT=$($TIMEOUT_BIN 5 $TCPDUMP_BIN -nni "veth2" net 10.0.0.0/8 -c 5 < /dev/null 2>/dev/null)
  ALT_COUNT=0
  if [ -n "$TCP_RAW_ALT" ]; then
    ALT_COUNT=$(echo "$TCP_RAW_ALT" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
  fi
  if [ "$ALT_COUNT" -gt "$TCP_COUNT" ]; then
    TCP_RAW="$TCP_RAW_ALT"
    TCP_COUNT="$ALT_COUNT"
  fi
fi

echo "##M|TCP|${TCP_COUNT}"
RAW_B64=$(printf "%s" "$TCP_RAW" | base64 | tr -d '\r\n')
echo "##RAW|TCP|${RAW_B64}"

# 7. SSL CHECK
SSL_LINES=""
SSL_OWNER=""
SSL_GROUP=""
SSL_MD5=""
SSL_RAW=""
if [ -f "$SSL_FILE" ]; then
  SSL_LINES=$(wc -l < "$SSL_FILE" 2>/dev/null | tr -d ' \r\n')
  SSL_OWNER=$(stat -c '%U' "$SSL_FILE" 2>/dev/null | tr -d '\r\n')
  SSL_GROUP=$(stat -c '%G' "$SSL_FILE" 2>/dev/null | tr -d '\r\n')
  SSL_MD5=$(md5sum "$SSL_FILE" 2>/dev/null | awk '{print $1}' | tr -d '\r\n')
  SSL_RAW=$(ls -l "$SSL_FILE" 2>/dev/null)
fi
echo "##M|SSL|${SSL_LINES}|${SSL_OWNER}|${SSL_GROUP}|${SSL_MD5}"
RAW_B64=$(printf "%s" "$SSL_RAW" | base64 | tr -d '\r\n')
echo "##RAW|SSL|${RAW_B64}"

# 8. DIAG2 CHECK
DIAG2_FOUND=""
DIAG2_RAW=""
if [ -x "$LOGDECODER" ]; then
  DIAG2_RAW=$($TIMEOUT_BIN 10 "$LOGDECODER" -i /var/opt/opwv/logs/*TrafficServerElement* -mlo < /dev/null 2>/dev/null | grep -i diagnostic2 | grep -i MSISDN | head -1)
  if [ -n "$DIAG2_RAW" ]; then
    DIAG2_FOUND="1"
  else
    DIAG2_FOUND="0"
  fi
else
  DIAG2_FOUND=""
fi
echo "##M|DIAG2|${DIAG2_FOUND}"
RAW_B64=$(printf "%s" "$DIAG2_RAW" | base64 | tr -d '\r\n')
echo "##RAW|DIAG2|${RAW_B64}"

echo "##END"
