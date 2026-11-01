#!/bin/bash
#########################################################################################################
# Smart-E HE Certificate Audit Script (ATS FE Level)                                                    #
# Contract:                                                                                             #
# ##META|<fe_hostname>|<oam_version>|<multicert_path>|<multicert_md5>|<entry_count>                     #
# ##CERT|<role>|<file_name>|<resolved_path>|<dest_ip>|<not_after_epoch>|<not_after_text>|<subject_cn>|<issuer_cn>|<serial>|<state>
# ##ERR|<code>|<message>                                                                                #
# ##END                                                                                                 #
#########################################################################################################

fe_hostname=$(hostname 2>/dev/null || uname -n 2>/dev/null || echo "unknown")

if [ ! -f /opt/opwv/ost/etc/vars ]; then
    printf "##ERR|%s|%s\n" "VARS_MISSING" "/opt/opwv/ost/etc/vars not found"
    printf "##END\n"
    exit 0
fi

oamversion=$(grep "OAM_VERSION" /opt/opwv/ost/etc/vars | cut -d "=" -f2 | tr -d ' \r\n')
if [ -z "$oamversion" ]; then
    oamversion="unknown"
fi

CERTS_PATH="/opt/opwv/integra/$oamversion/tools"
INPUT_FILE="/opt/opwv/integra/$oamversion/tools/trafficserver/etc/trafficserver/ssl_multicert.config"

if [ ! -f "$INPUT_FILE" ]; then
    printf "##ERR|%s|%s\n" "MULTICERT_MISSING" "$INPUT_FILE not found"
    printf "##END\n"
    exit 0
fi

multicert_md5=$(md5sum "$INPUT_FILE" 2>/dev/null | awk '{print $1}')
if [ -z "$multicert_md5" ]; then
    multicert_md5="unknown"
fi

entry_count=$(grep -v '^[[:space:]]*#' "$INPUT_FILE" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')

printf "##META|%s|%s|%s|%s|%s\n" "$fe_hostname" "$oamversion" "$INPUT_FILE" "$multicert_md5" "$entry_count"

declare -A CHECKED_PATHS

check_and_emit_cert() {
    local role="$1"
    local raw_path="$2"
    local dest_ip="$3"

    if [ -z "$raw_path" ]; then
        return
    fi

    local resolved_path=""
    if [[ "$raw_path" =~ ^/ ]]; then
        resolved_path="$raw_path"
    else
        resolved_path="${CERTS_PATH}/${raw_path}"
    fi

    # Deduplication by resolved full path
    if [[ -n "${CHECKED_PATHS[$resolved_path]}" ]]; then
        return
    fi
    CHECKED_PATHS["$resolved_path"]=1

    local file_name
    file_name=$(basename "$raw_path")

    if [ ! -f "$resolved_path" ]; then
        printf "##CERT|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
            "$role" "$file_name" "$resolved_path" "$dest_ip" "0" "File Not Found" "" "" "" "NOT_FOUND"
        return
    fi

    local openssl_out
    openssl_out=$(openssl x509 -enddate -subject -issuer -serial -noout -in "$resolved_path" 2>/dev/null)
    if [ -z "$openssl_out" ]; then
        printf "##CERT|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
            "$role" "$file_name" "$resolved_path" "$dest_ip" "0" "Invalid Certificate" "" "" "" "PARSE_ERROR"
        return
    fi

    local not_after_text
    not_after_text=$(echo "$openssl_out" | grep '^notAfter=' | cut -d= -f2-)

    local not_after_epoch="0"
    if [ -n "$not_after_text" ]; then
        not_after_epoch=$(date -d "$not_after_text" +%s 2>/dev/null || echo "0")
    fi

    local subject_cn
    subject_cn=$(echo "$openssl_out" | grep '^subject=' | sed -e 's/subject= *//' | tr '|' '/')

    local issuer_cn
    issuer_cn=$(echo "$openssl_out" | grep '^issuer=' | sed -e 's/issuer= *//' | tr '|' '/')

    local serial
    serial=$(echo "$openssl_out" | grep '^serial=' | cut -d= -f2- | tr '|' '/')

    printf "##CERT|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$role" "$file_name" "$resolved_path" "$dest_ip" "$not_after_epoch" "$not_after_text" "$subject_cn" "$issuer_cn" "$serial" "OK"
}

while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    dest_ip=$(echo "$line" | grep -oP 'dest_ip=\K[^ ]+' || echo "*")
    [ -z "$dest_ip" ] && dest_ip="*"

    cert_file=$(echo "$line" | grep -oP 'ssl_cert_name=\K[^ ]+')
    ca_file=$(echo "$line" | grep -oP 'ssl_ca_name=\K[^ ]+')

    [[ -n "$cert_file" ]] && check_and_emit_cert "cert" "$cert_file" "$dest_ip"
    [[ -n "$ca_file" ]] && check_and_emit_cert "ca" "$ca_file" "$dest_ip"
done < "$INPUT_FILE"

printf "##END\n"
