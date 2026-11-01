#!/usr/bin/env bash
###############################################################################
# Script Name : oam_kpi.sh
# Purpose     : Query ordb for success rate and anonymous request percentages
# Inputs      : DB_USER, DB_PASS (passed in environment or injected)
# Contract    : Tagged stdout output ##SR, ##ANON, ##ERR, ##END
###############################################################################

DB_USER="${DB_USER:-ordb}"
DB_PASS="${DB_PASS:-opr3pdb}"

oam_version=""
if [ -f /opt/opwv/ost/etc/vars ]; then
  oam_version=$(grep OAM_VERSION /opt/opwv/ost/etc/vars 2>/dev/null | cut -d "=" -f2 | tr -d '\r\n')
fi

MYSQL="/opt/opwv/oam/${oam_version:-8.4}/mysql/bin/mysql"
if [ ! -x "$MYSQL" ]; then
  # Fallback check for any mysql binary under /opt/opwv/oam
  MYSQL_CANDIDATE=$(ls -1 /opt/opwv/oam/*/mysql/bin/mysql 2>/dev/null | head -1)
  if [ -x "$MYSQL_CANDIDATE" ]; then
    MYSQL="$MYSQL_CANDIDATE"
  fi
fi

if [ ! -x "$MYSQL" ]; then
  echo "##ERR|MYSQL_MISSING|MySQL binary not found under /opt/opwv/oam/${oam_version:-8.4}/mysql/bin/mysql"
  echo "##END"
  exit 0
fi

export MYSQL_PWD="$DB_PASS"

# 1. SUCCESS RATE QUERY
# Computes per-host minimum success rate in the last 10 minutes
SR_OUTPUT=$($MYSQL -N -B -u "$DB_USER" -h 127.0.0.1 ordb -e "
select
t2.hostname,
t2.region,
t2.utc_ts,
t2.successrate
from (
  select
  utc_ts,
  hostname,
  region,
  IF(total_txns = 0, 0, ROUND((1 - total_errors / total_txns) * 100, 2)) as successrate
  from (
    select hostname, region, utc_ts,
    sum(txns) total_txns,
    sum(errors) total_errors
    from (
      select utc_ts,
      hostname,
      region,
      txn_count txns,
      IF(txn_count = 0, 0,
        (IF(cli_status_class in ('2','3') and int_status_class in ('4','5'), txn_count, err_count))
      ) errors
      from ordb.http_txn_stat_tbl
      where utc_ts > (SELECT MAX(utc_ts) - INTERVAL 10 MINUTE FROM ordb.http_txn_stat_tbl)
    ) t1
    group by hostname, region, utc_ts
  ) t_inner
) t2
inner join (
  select hostname, min(successrate) as min_sr
  from (
    select
    hostname,
    IF(total_txns = 0, 0, ROUND((1 - total_errors / total_txns) * 100, 2)) as successrate
    from (
      select hostname, utc_ts,
      sum(txn_count) total_txns,
      sum(IF(txn_count = 0, 0, (IF(cli_status_class in ('2','3') and int_status_class in ('4','5'), txn_count, err_count)))) total_errors
      from ordb.http_txn_stat_tbl
      where utc_ts > (SELECT MAX(utc_ts) - INTERVAL 10 MINUTE FROM ordb.http_txn_stat_tbl)
      group by hostname, utc_ts
    ) t_calc
  ) t_group
  group by hostname
) min_map on t2.hostname = min_map.hostname and t2.successrate = min_map.min_sr
group by t2.hostname;
" 2>&1)

SR_EXIT=$?
if [ $SR_EXIT -ne 0 ]; then
  if echo "$SR_OUTPUT" | grep -qi "access denied"; then
    echo "##ERR|DB_AUTH|MySQL authentication failed for user $DB_USER"
  else
    echo "##ERR|DB_QUERY|MySQL query error: $(echo "$SR_OUTPUT" | tr '\n' ' ')"
  fi
else
  echo "$SR_OUTPUT" | grep -v '\[Warning\]' | while read -r host reg ts tm sr; do
    if [ -n "$host" ] && [ -n "$sr" ] && [ "$host" != "mysql:" ]; then
      echo "##SR|${host}|${reg}|${ts} ${tm}|${sr}"
    fi
  done
fi

# 2. ANONYMOUS REQUEST QUERY
# Computes per-host maximum anonymous % in the last 5 minutes
ANON_OUTPUT=$($MYSQL -N -B -u "$DB_USER" -h 127.0.0.1 ordb -e "
select
t2.hostname,
t2.region,
t2.utc_ts,
t2.anon_perc
from (
  select
  utc_ts,
  hostname,
  region,
  IF(txn_count = 0, 0, ROUND(100 * (anon_count / txn_count), 2)) as anon_perc
  from ordb.http_anon_stat_tbl
  where utc_ts > (SELECT MAX(utc_ts) - INTERVAL 5 MINUTE FROM ordb.http_anon_stat_tbl)
) t2
inner join (
  select hostname, max(IF(txn_count = 0, 0, ROUND(100 * (anon_count / txn_count), 2))) as max_anon
  from ordb.http_anon_stat_tbl
  where utc_ts > (SELECT MAX(utc_ts) - INTERVAL 5 MINUTE FROM ordb.http_anon_stat_tbl)
  group by hostname
) max_map on t2.hostname = max_map.hostname and t2.anon_perc = max_map.max_anon
group by t2.hostname;
" 2>&1)

ANON_EXIT=$?
if [ $ANON_EXIT -ne 0 ]; then
  if echo "$ANON_OUTPUT" | grep -qi "access denied"; then
    echo "##ERR|DB_AUTH|MySQL authentication failed for user $DB_USER"
  else
    echo "##ERR|DB_QUERY|MySQL query error: $(echo "$ANON_OUTPUT" | tr '\n' ' ')"
  fi
else
  echo "$ANON_OUTPUT" | grep -v '\[Warning\]' | while read -r host reg ts tm anon; do
    if [ -n "$host" ] && [ -n "$anon" ] && [ "$host" != "mysql:" ]; then
      echo "##ANON|${host}|${reg}|${ts} ${tm}|${anon}"
    fi
  done
fi

echo "##END"
