#!/bin/bash
#########################################################################################################
# Smart-E HE SSL Multicert Manager Script (ATS FE Level)                                                #
# Modes:                                                                                                #
#   1. inspect (default)                                                                                #
#   2. sca_status                                                                                       #
#   3. update <block_name> <new_cert> <new_key> <new_ca>                                                #
#########################################################################################################

run_ssl_multicert() {
    ACTION="${1:-inspect}"
    shift 2>/dev/null || true

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

TOOLS_DIR="/opt/opwv/integra/$oamversion/tools"
CERTS_DIR="/opt/opwv/integra/$oamversion/tools/certs"
INPUT_FILE="/opt/opwv/integra/$oamversion/tools/trafficserver/etc/trafficserver/ssl_multicert.config"

OAMSCA_INIT="/etc/init.d/oamsca-v$oamversion"
if [ ! -x "$OAMSCA_INIT" ]; then
    OAMSCA_INIT=$(ls -d /etc/init.d/oamsca-v* 2>/dev/null | head -1)
fi
if [ ! -x "$OAMSCA_INIT" ]; then
    OAMSCA_INIT=$(ls -d /etc/init.d/oamsca* 2>/dev/null | head -1)
fi

if [ ! -f "$INPUT_FILE" ]; then
    printf "##ERR|%s|%s\n" "MULTICERT_MISSING" "$INPUT_FILE not found"
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# Helper: Resolve full path of cert / key / ca                                                          #
#########################################################################################################
resolve_cert_path() {
    local raw="$1"
    [ -z "$raw" ] && return
    if [[ "$raw" =~ ^/ ]]; then
        echo "$raw"
    elif [[ "$raw" =~ ^certs/ ]]; then
        echo "${TOOLS_DIR}/${raw}"
    else
        echo "${CERTS_DIR}/${raw}"
    fi
}

#########################################################################################################
# MODE: INSPECT                                                                                         #
#########################################################################################################
if [ "$ACTION" = "inspect" ]; then
    multicert_md5=$(md5sum "$INPUT_FILE" 2>/dev/null | awk '{print $1}')
    [ -z "$multicert_md5" ] && multicert_md5="unknown"
    total_lines=$(wc -l < "$INPUT_FILE" 2>/dev/null | tr -d ' ')

    printf "##META|%s|%s|%s|%s|%s|%s\n" \
        "$fe_hostname" "$oamversion" "$INPUT_FILE" "$CERTS_DIR" "$multicert_md5" "$total_lines"

    declare -A USED_FILES
    declare -A FILE_CACHE_EXP
    declare -A FILE_CACHE_TXT
    declare -A FILE_CACHE_CN

    # 1. Scan all files in CERTS_DIR
    if [ -d "$CERTS_DIR" ]; then
        for f in "$CERTS_DIR"/*; do
            [ -f "$f" ] || continue
            fname=$(basename "$f")
            fsize=$(stat -c %s "$f" 2>/dev/null || wc -c < "$f" 2>/dev/null || echo "0")
            fmtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")

            ftype="other"
            case "$fname" in
                *.key|*private*) ftype="key" ;;
                *ca-bundle*|*CA*|*bundle*) ftype="ca" ;;
                *.crt|*.cer|*.pem) ftype="cert" ;;
            esac

            not_after_epoch="0"
            not_after_text=""
            subject_cn=""

            if [ "$ftype" = "cert" ] || [ "$ftype" = "ca" ]; then
                openssl_out=$(openssl x509 -enddate -subject -noout -in "$f" 2>/dev/null)
                if [ -n "$openssl_out" ]; then
                    not_after_text=$(echo "$openssl_out" | grep '^notAfter=' | cut -d= -f2-)
                    if [ -n "$not_after_text" ]; then
                        not_after_epoch=$(date -d "$not_after_text" +%s 2>/dev/null || echo "0")
                    fi
                    subject_cn=$(echo "$openssl_out" | grep '^subject=' | sed -e 's/subject= *//' | tr '|' '/')
                fi
            fi

            FILE_CACHE_EXP["$fname"]="$not_after_epoch"
            FILE_CACHE_TXT["$fname"]="$not_after_text"
            FILE_CACHE_CN["$fname"]="$subject_cn"

            printf "##DIR_FILE|%s|%s|%s|%s|%s|%s|%s\n" \
                "$fname" "$fsize" "$fmtime" "$ftype" "$not_after_epoch" "$not_after_text" "$subject_cn"
        done
    fi

    # 2. Parse ssl_multicert.config lines and blocks
    current_block="General"
    block_emitted=0

    while IFS= read -r line || [ -n "$line" ]; do
        # Detect comment headers for block names
        # Format like: ####################Authtelkomsel####################
        if [[ "$line" =~ ^[[:space:]]*#{2,}[[:space:]]*([^#]+)[[:space:]]*#{2,}[[:space:]]*$ ]]; then
            header_cand="${BASH_REMATCH[1]}"
            header_cand=$(echo "$header_cand" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            # Filter out documentation headers
            if [[ ! "$header_cand" =~ ^(ssl_multicert\.config|Allows a TLS|dest_ip=|ssl_key_name=|ssl_ca_name=|ssl_cert_name=|Examples:|Fields:)$ ]]; then
                current_block="$header_cand"
                printf "##BLOCK_START|%s\n" "$current_block"
                continue
            fi
        fi

        # Check for dest_ip entry (active or commented out)
        is_commented=0
        clean_line="$line"
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*(dest_ip=.*) ]]; then
            is_commented=1
            clean_line="${BASH_REMATCH[1]}"
        elif [[ ! "$line" =~ ^[[:space:]]*dest_ip= ]]; then
            continue
        fi

        dest_ip=$(echo "$clean_line" | grep -oP 'dest_ip=\K[^ ]+' || echo "*")
        cert_file=$(echo "$clean_line" | grep -oP 'ssl_cert_name=\K[^ ]+' || echo "")
        key_file=$(echo "$clean_line" | grep -oP 'ssl_key_name=\K[^ ]+' || echo "")
        ca_file=$(echo "$clean_line" | grep -oP 'ssl_ca_name=\K[^ ]+' || echo "")

        [ -z "$dest_ip" ] && continue
        [ -z "$cert_file" ] && continue

        # Ignore ATS example comments from documentation header
        if [[ "$cert_file" =~ ^(bar\.pem|server\.pem|foo\.pem)$ ]]; then
            continue
        fi

        # Check existence on remote disk
        cert_exists=0
        full_cert=$(resolve_cert_path "$cert_file")
        if [ -n "$full_cert" ] && [ -f "$full_cert" ]; then
            cert_exists=1
        fi

        key_exists=1
        if [ -n "$key_file" ]; then
            full_key=$(resolve_cert_path "$key_file")
            if [ ! -f "$full_key" ]; then
                key_exists=0
            fi
        fi

        ca_exists=1
        if [ -n "$ca_file" ]; then
            full_ca=$(resolve_cert_path "$ca_file")
            if [ ! -f "$full_ca" ]; then
                ca_exists=0
            fi
        fi

        # Record used files
        [ -n "$cert_file" ] && USED_FILES["$(basename "$cert_file")"]=1
        [ -n "$key_file" ] && USED_FILES["$(basename "$key_file")"]=1
        [ -n "$ca_file" ] && USED_FILES["$(basename "$ca_file")"]=1

        cert_base=$(basename "$cert_file")
        not_after_epoch="${FILE_CACHE_EXP[$cert_base]:-0}"
        not_after_text="${FILE_CACHE_TXT[$cert_base]:-}"

        printf "##ENTRY|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
            "$dest_ip" "$cert_file" "$key_file" "$ca_file" "$is_commented" \
            "$cert_exists" "$key_exists" "$ca_exists" "$not_after_epoch" "$not_after_text"
    done < "$INPUT_FILE"

    # 3. Emit Unused Files in CERTS_DIR
    if [ -d "$CERTS_DIR" ]; then
        for f in "$CERTS_DIR"/*; do
            [ -f "$f" ] || continue
            fname=$(basename "$f")
            if [ -z "${USED_FILES[$fname]}" ]; then
                fsize=$(stat -c %s "$f" 2>/dev/null || wc -c < "$f" 2>/dev/null || echo "0")
                fmtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")

                ftype="other"
                case "$fname" in
                    *.key|*private*) ftype="key" ;;
                    *ca-bundle*|*CA*|*bundle*) ftype="ca" ;;
                    *.crt|*.cer|*.pem) ftype="cert" ;;
                esac

                not_after_epoch="${FILE_CACHE_EXP[$fname]:-0}"
                not_after_text="${FILE_CACHE_TXT[$fname]:-}"
                subject_cn="${FILE_CACHE_CN[$fname]:-}"

                printf "##UNUSED|%s|%s|%s|%s|%s|%s|%s\n" \
                    "$fname" "$fsize" "$fmtime" "$ftype" "$not_after_epoch" "$not_after_text" "$subject_cn"
            fi
        done
    fi

    # 4. Emit Raw Config Base64
    b64_cfg=$(base64 "$INPUT_FILE" 2>/dev/null | tr -d '\r\n')
    printf "##RAW_B64|%s\n" "$b64_cfg"

    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: SCA_STATUS                                                                                      #
#########################################################################################################
if [ "$ACTION" = "sca_status" ]; then
    if [ ! -x "$OAMSCA_INIT" ]; then
        printf "##ERR|%s|%s\n" "OAMSCA_NOT_FOUND" "OAMSCA init script ($OAMSCA_INIT) not found or not executable"
        printf "##END\n"
        exit 1
    fi

    raw_sca=$("$OAMSCA_INIT" status 2>&1)
    b64_sca=$(echo "$raw_sca" | base64 2>/dev/null | tr -d '\r\n')
    tse_line=$(echo "$raw_sca" | grep -i 'TrafficServerElement' | head -1)
    tse_pid=""
    tse_iid=""
    if [ -n "$tse_line" ]; then
        tse_pid=$(echo "$tse_line" | grep -oP '\(\s*\K[0-9]+(?=/[0-9]+)' 2>/dev/null)
        if [ -z "$tse_pid" ]; then
            tse_pid=$(echo "$tse_line" | sed -n 's/.*(\s*\([0-9]\+\)\/\([0-9]\+\).*/\1/p')
        fi
        tse_iid=$(echo "$tse_line" | grep -oP '\(.*?\)' | grep -oP '/\s*\K[0-9]+' | head -1 2>/dev/null)
        if [ -z "$tse_iid" ]; then
            tse_iid=$(echo "$tse_line" | sed -n 's/.*(\s*\([0-9]\+\)\/\([0-9]\+\).*/\2/p')
        fi
    fi

    printf "##SCA_STATUS|%s|%s|%s\n" "$OAMSCA_INIT" "${tse_pid:-unknown}" "${tse_iid:-unknown}"
    printf "##SCA_RAW_B64|%s\n" "$b64_sca"
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: UPDATE                                                                                          #
# Args: <block_name> <new_cert> <new_key> <new_ca> [override_instance_id]                              #
#########################################################################################################
if [ "$ACTION" = "update" ]; then
    TARGET_BLOCK="$1"
    NEW_CERT="$2"
    NEW_KEY="$3"
    NEW_CA="$4"
    OVERRIDE_IID="$5"

    if [ -z "$TARGET_BLOCK" ]; then
        printf "##ERR|%s|%s\n" "INVALID_ARGS" "Target block name is required"
        printf "##END\n"
        exit 1
    fi

    # Validate that files exist if specified
    if [ -n "$NEW_CERT" ]; then
        p_cert=$(resolve_cert_path "$NEW_CERT")
        if [ ! -f "$p_cert" ]; then
            printf "##ERR|%s|%s\n" "CERT_NOT_FOUND" "Specified certificate file not found on remote: $p_cert"
            printf "##END\n"
            exit 1
        fi
    fi

    if [ -n "$NEW_KEY" ] && [ "$NEW_KEY" != "__NONE__" ]; then
        p_key=$(resolve_cert_path "$NEW_KEY")
        if [ ! -f "$p_key" ]; then
            printf "##ERR|%s|%s\n" "KEY_NOT_FOUND" "Specified key file not found on remote: $p_key"
            printf "##END\n"
            exit 1
        fi
    fi

    if [ -n "$NEW_CA" ] && [ "$NEW_CA" != "__NONE__" ]; then
        p_ca=$(resolve_cert_path "$NEW_CA")
        if [ ! -f "$p_ca" ]; then
            printf "##ERR|%s|%s\n" "CA_NOT_FOUND" "Specified CA file not found on remote: $p_ca"
            printf "##END\n"
            exit 1
        fi
    fi

    # Create timestamped backup
    ts=$(date +%Y%m%d_%H%M%S)
    backup_file="${INPUT_FILE}.bak_${ts}"
    cp -p "$INPUT_FILE" "$backup_file"
    if [ $? -ne 0 ]; then
        printf "##ERR|%s|%s\n" "BACKUP_FAILED" "Failed to create backup: $backup_file"
        printf "##END\n"
        exit 1
    fi

    tmp_file=$(mktemp)
    in_target_block=0
    matched_lines=0

    while IFS= read -r line || [ -n "$line" ]; do
        # Check header
        if [[ "$line" =~ ^[[:space:]]*#{2,}[[:space:]]*([^#]+)[[:space:]]*#{2,}[[:space:]]*$ ]]; then
            header_cand="${BASH_REMATCH[1]}"
            header_cand=$(echo "$header_cand" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "$header_cand" = "$TARGET_BLOCK" ]; then
                in_target_block=1
            else
                in_target_block=0
            fi
            echo "$line" >> "$tmp_file"
            continue
        fi

        # If inside target block and is a dest_ip line (active or commented)
        if [ $in_target_block -eq 1 ] && [[ "$line" =~ dest_ip= ]]; then
            mod_line="$line"
            if [ -n "$NEW_CERT" ]; then
                mod_line=$(echo "$mod_line" | sed -r "s|ssl_cert_name=[^ ]+|ssl_cert_name=${NEW_CERT}|")
            fi
            if [ "$NEW_KEY" = "__NONE__" ]; then
                mod_line=$(echo "$mod_line" | sed -r "s|[[:space:]]*ssl_key_name=[^ ]+||")
            elif [ -n "$NEW_KEY" ]; then
                if [[ "$mod_line" =~ ssl_key_name= ]]; then
                    mod_line=$(echo "$mod_line" | sed -r "s|ssl_key_name=[^ ]+|ssl_key_name=${NEW_KEY}|")
                else
                    mod_line="${mod_line} ssl_key_name=${NEW_KEY}"
                fi
            fi
            if [ "$NEW_CA" = "__NONE__" ]; then
                mod_line=$(echo "$mod_line" | sed -r "s|[[:space:]]*ssl_ca_name=[^ ]+||")
            elif [ -n "$NEW_CA" ]; then
                if [[ "$mod_line" =~ ssl_ca_name= ]]; then
                    mod_line=$(echo "$mod_line" | sed -r "s|ssl_ca_name=[^ ]+|ssl_ca_name=${NEW_CA}|")
                else
                    mod_line="${mod_line} ssl_ca_name=${NEW_CA}"
                fi
            fi
            echo "$mod_line" >> "$tmp_file"
            matched_lines=$((matched_lines + 1))
        else
            echo "$line" >> "$tmp_file"
        fi
    done < "$INPUT_FILE"

    if [ $matched_lines -eq 0 ]; then
        rm -f "$tmp_file"
        printf "##ERR|%s|%s\n" "BLOCK_NOT_FOUND" "No matching entries found for block: $TARGET_BLOCK"
        printf "##END\n"
        exit 1
    fi

    # Replace config
    cat "$tmp_file" > "$INPUT_FILE"
    chmod 644 "$INPUT_FILE" 2>/dev/null || true
    chown opwv:opwv "$INPUT_FILE" 2>/dev/null || true
    new_md5=$(md5sum "$INPUT_FILE" | awk '{print $1}')

    # Generate diff
    diff_output=$(diff -u "$backup_file" "$INPUT_FILE" 2>/dev/null || true)
    rm -f "$tmp_file"

    # 1. Query status OAMSCA sebelum restart
    sca_status_before=""
    instance_id="$OVERRIDE_IID"
    process_id=""
    if [ -x "$OAMSCA_INIT" ]; then
        sca_status_before=$("$OAMSCA_INIT" status 2>&1)
        tse_line=$(echo "$sca_status_before" | grep -i 'TrafficServerElement' | head -1)
        if [ -n "$tse_line" ]; then
            process_id=$(echo "$tse_line" | grep -oP '\(\s*\K[0-9]+(?=/[0-9]+)' 2>/dev/null)
            if [ -z "$process_id" ]; then
                process_id=$(echo "$tse_line" | sed -n 's/.*(\s*\([0-9]\+\)\/\([0-9]\+\).*/\1/p')
            fi
            if [ -z "$instance_id" ]; then
                instance_id=$(echo "$tse_line" | grep -oP '\(.*?\)' | grep -oP '/\s*\K[0-9]+' | head -1 2>/dev/null)
                if [ -z "$instance_id" ]; then
                    instance_id=$(echo "$tse_line" | sed -n 's/.*(\s*\([0-9]\+\)\/\([0-9]\+\).*/\2/p')
                fi
            fi
        fi
    fi

    # 2. Restart service oamsca dengan instance_id
    restart_cmd=""
    restart_out=""
    reload_msg=""
    sca_status_after=""
    sca_init_log_output=""
    sca_init_log_file="/var/opt/opwv/logs/scaInit.log"

    lines_before=0
    if [ -f "$sca_init_log_file" ]; then
        lines_before=$(wc -l < "$sca_init_log_file" 2>/dev/null || echo 0)
    fi

    if [ -n "$instance_id" ] && [ -x "$OAMSCA_INIT" ]; then
        restart_cmd="$OAMSCA_INIT restart $instance_id"
        restart_out=$($restart_cmd 2>&1)
        reload_msg="OAMSCA restarted TrafficServerElement (instance $instance_id)"
        
        # Sleep to allow OAMSCA element initialization to log to scaInit.log
        sleep 3

        # Capture newly appended lines from scaInit.log, or fallback to tail 40 lines
        if [ -f "$sca_init_log_file" ]; then
            sca_init_log_output=$(tail -n +$((lines_before + 1)) "$sca_init_log_file" 2>/dev/null | head -100)
            if [ -z "$sca_init_log_output" ]; then
                sca_init_log_output=$(tail -n 40 "$sca_init_log_file" 2>/dev/null)
            fi
        else
            sca_init_log_output="Log file $sca_init_log_file not found or not readable."
        fi

        sca_status_after=$("$OAMSCA_INIT" status 2>&1)
    else
        reload_msg="TrafficServerElement instance_id not detected or OAMSCA not executable"
        sca_status_after="$sca_status_before"
        if [ -f "$sca_init_log_file" ]; then
            sca_init_log_output=$(tail -n 30 "$sca_init_log_file" 2>/dev/null)
        fi
    fi

    b64_sca_before=$(echo "$sca_status_before" | base64 2>/dev/null | tr -d '\r\n')
    b64_sca_after=$(echo "$sca_status_after" | base64 2>/dev/null | tr -d '\r\n')
    b64_sca_init_log=$(echo "$sca_init_log_output" | base64 2>/dev/null | tr -d '\r\n')

    printf "##UPDATE_RESULT|SUCCESS|%s|%s|%s|%s\n" "$backup_file" "$new_md5" "$reload_msg" "$instance_id"
    printf "##DIFF_START\n"
    printf "%s\n" "$diff_output"
    printf "##DIFF_END\n"
    printf "##RESTART_CMD|%s\n" "$restart_cmd"
    printf "##RESTART_LOG_START\n"
    printf "%s\n" "$restart_out"
    printf "##RESTART_LOG_END\n"
    printf "##SCA_BEFORE_B64|%s\n" "$b64_sca_before"
    printf "##SCA_AFTER_B64|%s\n" "$b64_sca_after"
    printf "##SCA_INIT_LOG_B64|%s\n" "$b64_sca_init_log"
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: FETCH_SCA_INIT_LOG                                                                              #
# Args: [lines]                                                                                         #
#########################################################################################################
if [ "$ACTION" = "fetch_sca_init_log" ]; then
    log_lines="${1:-50}"
    sca_log="/var/opt/opwv/logs/scaInit.log"
    if [ -f "$sca_log" ]; then
        log_out=$(tail -n "$log_lines" "$sca_log" 2>/dev/null)
        b64_log=$(echo "$log_out" | base64 2>/dev/null | tr -d '\r\n')
        printf "##SCA_INIT_LOG_RESULT|SUCCESS|%s\n" "$sca_log"
        printf "##SCA_INIT_LOG_B64|%s\n" "$b64_log"
    else
        printf "##ERR|%s|%s\n" "FILE_NOT_FOUND" "Log file $sca_log not found"
    fi
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: UPLOAD_CERT                                                                                     #
# Args: <filename> <base64_content>                                                                     #
#########################################################################################################
if [ "$ACTION" = "upload_cert" ]; then
    FNAME="$1"
    B64_CONTENT="$2"

    if [ -z "$FNAME" ] || [ -z "$B64_CONTENT" ]; then
        printf "##ERR|%s|%s\n" "INVALID_ARGS" "Filename and base64 content are required"
        printf "##END\n"
        exit 1
    fi

    # Strip any directory traversal or path prefixes
    clean_fname=$(basename "$FNAME")

    # 1. Backup CERTS_DIR if exists and not yet backed up in this timestamp minute
    ts=$(date +%Y%m%d_%H%M)
    backup_certs_dir="${CERTS_DIR}.bak_${ts}"
    if [ -d "$CERTS_DIR" ] && [ ! -d "$backup_certs_dir" ]; then
        cp -rp "$CERTS_DIR" "$backup_certs_dir" 2>/dev/null || true
    fi

    # 2. Ensure folder has chmod 755 and chown opwv:opwv
    mkdir -p "$CERTS_DIR" 2>/dev/null
    chmod 755 "$CERTS_DIR" 2>/dev/null || true
    chown opwv:opwv "$CERTS_DIR" 2>/dev/null || true

    target_path="${CERTS_DIR}/${clean_fname}"

    printf "%s" "$B64_CONTENT" | base64 -d > "$target_path"
    if [ $? -ne 0 ] || [ ! -f "$target_path" ]; then
        printf "##ERR|%s|%s\n" "WRITE_FAILED" "Failed to write file to $target_path"
        printf "##END\n"
        exit 1
    fi

    # 3. Ensure target file has chmod 755 and chown opwv:opwv
    chmod 755 "$target_path" 2>/dev/null || true
    chown opwv:opwv "$target_path" 2>/dev/null || true
    fsize=$(stat -c %s "$target_path" 2>/dev/null || wc -c < "$target_path" 2>/dev/null || echo "0")
    fmd5=$(md5sum "$target_path" 2>/dev/null | awk '{print $1}')

    printf "##UPLOAD_RESULT|SUCCESS|%s|%s|%s\n" "$clean_fname" "$fsize" "$fmd5"
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: FETCH_FILE_B64                                                                                  #
# Args: <filename>                                                                                      #
#########################################################################################################
if [ "$ACTION" = "fetch_file_b64" ]; then
    FNAME="$1"
    clean_fname=$(basename "$FNAME")
    target_path=$(resolve_cert_path "$clean_fname")

    if [ ! -f "$target_path" ]; then
        printf "##ERR|%s|%s\n" "FILE_NOT_FOUND" "File $clean_fname not found in certs directory"
        printf "##END\n"
        exit 1
    fi

    b64_content=$(base64 < "$target_path" 2>/dev/null | tr -d '\r\n')
    fsize=$(stat -c %s "$target_path" 2>/dev/null || wc -c < "$target_path" 2>/dev/null || echo "0")

    printf "##FETCH_RESULT|SUCCESS|%s|%s|%s\n" "$clean_fname" "$fsize" "$b64_content"
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: LIST_CERTS                                                                                      #
#########################################################################################################
if [ "$ACTION" = "list_certs" ]; then
    if [ -d "$CERTS_DIR" ]; then
        for f in "$CERTS_DIR"/*; do
            [ -f "$f" ] || continue
            fname=$(basename "$f")
            printf "##CERT_FILE|%s\n" "$fname"
        done
    fi
    printf "##END\n"
    exit 0
fi

#########################################################################################################
# MODE: DELETE_CERT                                                                                     #
# Args: <filename>                                                                                      #
#########################################################################################################
if [ "$ACTION" = "delete_cert" ]; then
    FNAME="$1"
    if [ -z "$FNAME" ]; then
        printf "##ERR|%s|%s\n" "INVALID_ARGS" "Filename is required"
        printf "##END\n"
        exit 1
    fi

    clean_fname=$(basename "$FNAME")
    target_path="${CERTS_DIR}/${clean_fname}"

    if [ ! -f "$target_path" ]; then
        printf "##ERR|%s|%s\n" "FILE_NOT_FOUND" "File $clean_fname not found in certs directory"
        printf "##END\n"
        exit 1
    fi

    # Backup CERTS_DIR if exists and not yet backed up in this timestamp minute
    ts=$(date +%Y%m%d_%H%M)
    backup_certs_dir="${CERTS_DIR}.bak_${ts}"
    if [ -d "$CERTS_DIR" ] && [ ! -d "$backup_certs_dir" ]; then
        cp -rp "$CERTS_DIR" "$backup_certs_dir" 2>/dev/null || true
    fi

    rm -f "$target_path" 2>/dev/null
    if [ -f "$target_path" ]; then
        printf "##ERR|%s|%s\n" "DELETE_FAILED" "Failed to delete $clean_fname"
        printf "##END\n"
        exit 1
    fi

    printf "##DELETE_RESULT|SUCCESS|%s\n" "$clean_fname"
    printf "##END\n"
    exit 0
fi

printf "##ERR|%s|%s\n" "UNKNOWN_ACTION" "Unknown action: $ACTION"
printf "##END\n"
exit 1
}

# Execute main function automatically if not suppressed by caller
if [ "${MULTICERT_NO_AUTO_RUN:-0}" != "1" ]; then
    run_ssl_multicert "$@"
fi
