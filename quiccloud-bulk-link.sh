#!/bin/bash
# ============================================================================
#  quiccloud-bulk-link.sh — Bulk QUIC.cloud Init + Link
#  Version: 1.0
#  Updated: 2026-04-28 01:00 (UTC+7)
#  Repo   : https://github.com/AnonymousVS/QuicCloud-Bulk-Link
# ============================================================================
# ไฟล์ Config (2 ไฟล์):
#   1. server-config.conf → QC_KEYS (email→api_key), Telegram, ตัวเลือก
#   2. domains.csv → domain,qc_email (ว่าง = ทุกเว็บ)
# ============================================================================
# วิธีรัน:
#   curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/server-config.conf \
#       -o /tmp/server-config.conf && \
#   curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/domains.csv \
#       -o /tmp/domains.csv && \
#   bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/quiccloud-bulk-link.sh)
# ============================================================================
# CHANGELOG:
# v1.0 (2026-04-28)
#   - Init + Link QUIC.cloud แบบ bulk
#   - Multi-account: QC_KEYS["email"]="api_key" per email
#   - domains.csv: domain,qc_email (ระบุเฉพาะ หรือว่าง = ทุกเว็บ)
#   - Parked/Alias domain detect จาก /etc/userdatadomains
#   - Retry + cooldown สำหรับ rate limit
#   - Telegram HTML notification
#   - Spinner + clean output
# ============================================================================

VERSION="v1.0"
PUBLIC_REPO="AnonymousVS/QuicCloud-Bulk-Link"
SERVER_CONFIG_FILE="server-config.conf"
DOMAINS_CSV_FILE="domains.csv"

# ─── ค้นหา + โหลด server-config.conf ────────────────────────
SERVER_CONFIG=""
if [[ -f "/tmp/$SERVER_CONFIG_FILE" ]]; then
    SERVER_CONFIG="/tmp/$SERVER_CONFIG_FILE"
elif [[ -f "/usr/local/etc/quiccloud-bulk-link/$SERVER_CONFIG_FILE" ]]; then
    SERVER_CONFIG="/usr/local/etc/quiccloud-bulk-link/$SERVER_CONFIG_FILE"
else
    echo "📥 ดาวน์โหลด server-config.conf จาก GitHub..."
    curl -fsSL "https://raw.githubusercontent.com/$PUBLIC_REPO/main/server-config.conf" \
        -o "/tmp/$SERVER_CONFIG_FILE" 2>/dev/null
    if [[ $? -eq 0 && -s "/tmp/$SERVER_CONFIG_FILE" ]]; then
        SERVER_CONFIG="/tmp/$SERVER_CONFIG_FILE"
    else
        echo "❌ ดาวน์โหลด server-config.conf ไม่สำเร็จ"
        exit 1
    fi
fi
echo "📄 Server Config: $SERVER_CONFIG"
source "$SERVER_CONFIG"

# ─── ค้นหา + โหลด domains.csv (optional) ────────────────────
# Format: domain,qc_email
DOMAINS_CSV=""
declare -A TARGET_DOMAINS
declare -A DOMAIN_QC_EMAIL
TARGET_DOMAIN_COUNT=0

if [[ -f "/tmp/$DOMAINS_CSV_FILE" ]]; then
    DOMAINS_CSV="/tmp/$DOMAINS_CSV_FILE"
elif [[ -f "/usr/local/etc/quiccloud-bulk-link/$DOMAINS_CSV_FILE" ]]; then
    DOMAINS_CSV="/usr/local/etc/quiccloud-bulk-link/$DOMAINS_CSV_FILE"
else
    curl -fsSL "https://raw.githubusercontent.com/$PUBLIC_REPO/main/domains.csv" \
        -o "/tmp/$DOMAINS_CSV_FILE" 2>/dev/null
    if [[ $? -eq 0 && -s "/tmp/$DOMAINS_CSV_FILE" ]]; then
        DOMAINS_CSV="/tmp/$DOMAINS_CSV_FILE"
    fi
fi

if [[ -n "$DOMAINS_CSV" ]]; then
    while IFS=',' read -r _dom _email; do
        _dom=$(echo "$_dom" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        _email=$(echo "$_email" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        [[ -z "$_dom" || "$_dom" == "domain" ]] && continue
        TARGET_DOMAINS["$_dom"]=1
        DOMAIN_QC_EMAIL["$_dom"]="$_email"
        TARGET_DOMAIN_COUNT=$((TARGET_DOMAIN_COUNT+1))
    done < "$DOMAINS_CSV"
    echo "📋 domains.csv: $DOMAINS_CSV ($TARGET_DOMAIN_COUNT domains)"
else
    echo "📋 domains.csv: ไม่มี (ทุกเว็บ)"
fi

# ─── Validate QC_KEYS ────────────────────────────────────────
QC_KEY_COUNT=${#QC_KEYS[@]}
if [[ $QC_KEY_COUNT -eq 0 ]]; then
    echo "❌ ERROR: ไม่พบ QC_KEYS ใน server-config.conf"
    exit 1
fi
echo "🔑 QC Accounts: $QC_KEY_COUNT"

# ─── Runtime ─────────────────────────────────────────────────
LINK_RETRY=${LINK_RETRY:-5}
LINK_COOLDOWN=${LINK_COOLDOWN:-3}
MAX_JOBS=1    # QUIC.cloud rate limit → ทำทีละเว็บ
WP_TIMEOUT=60

# ─── แสดง Confirm ───────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════"
echo "║   ☁️  quiccloud-bulk-link.sh  $VERSION"
echo "║   QUIC.cloud Bulk Init + Link"
echo "╠══════════════════════════════════════════════════════════════"
echo "║"
echo "║   QC Accounts  :  $QC_KEY_COUNT"
for _qk_email in "${!QC_KEYS[@]}"; do
    printf "║     %-40s %s...\n" "$_qk_email" "${QC_KEYS[$_qk_email]:0:8}"
done
echo "║"
echo "║   cPanel Users :  ${CPANEL_USERS:-"(ทุก user บน server)"}"
echo "║   domains.csv  :  ${TARGET_DOMAIN_COUNT:-0} domains"
echo "║   Retry        :  $LINK_RETRY ครั้ง"
echo "║   Cooldown     :  $LINK_COOLDOWN วินาที"
echo "║   Telegram     :  $( [[ -n "$TELEGRAM_BOT_TOKEN" ]] && echo "ON" || echo "OFF" )"
echo "║"
echo "╚══════════════════════════════════════════════════════════════"
echo ""
read -rp "  ▶  ยืนยัน? [y/N] : " _CONFIRM
echo ""
if [[ ! "$_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "🚫 ยกเลิก"
    exit 0
fi

# ─── Log + Result ────────────────────────────────────────────
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/quiccloud-bulk-link.log"
LOG_PASS="$LOG_DIR/quiccloud-bulk-link-pass.log"
LOG_FAIL="$LOG_DIR/quiccloud-bulk-link-fail.log"
LOG_SKIP="$LOG_DIR/quiccloud-bulk-link-skip.log"
LOCK_FILE="/tmp/quiccloud-bulk-link.lock"
RESULT_DIR=$(mktemp -d /tmp/qcbl-result.XXXXXX)
PROGRESS_PID=""
START_TIME=$(date +%s)

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf "\r\033[K"
    echo "$1"
    echo "[$ts] $1" >> "$LOG_FILE"
}

cleanup() {
    [[ -n "$spinner_pid" ]] && kill "$spinner_pid" 2>/dev/null
    [[ -n "$PROGRESS_PID" ]] && kill "$PROGRESS_PID" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$RESULT_DIR"
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

log "======================================"
log " QUIC.cloud Bulk Init + Link  $VERSION"
log " เริ่มเวลา    : $(date '+%Y-%m-%d %H:%M:%S')"
log " Server       : $(hostname)"
log " QC Accounts  : $QC_KEY_COUNT"
log " domains.csv  : ${DOMAINS_CSV:-"(ไม่มี — ทุกเว็บ)"} ($TARGET_DOMAIN_COUNT domains)"
log " cPanel Users : ${CPANEL_USERS:-"(ทุก user)"}"
log " Retry        : $LINK_RETRY"
log " Cooldown     : $LINK_COOLDOWN"
log " Telegram     : $( [[ -n "$TELEGRAM_BOT_TOKEN" ]] && echo "ON" || echo "OFF" )"
log "======================================"

# ─── Spinner ──────────────────────────────────────────────────
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
spinner_pid=""
start_spinner() {
    local msg="$1"
    (
        local i=0
        while true; do
            printf "\r  %s %s " "${SPINNER_CHARS:i%${#SPINNER_CHARS}:1}" "$msg"
            i=$((i+1))
            sleep 0.1
        done
    ) &
    spinner_pid=$!
}
stop_spinner() {
    [[ -n "$spinner_pid" ]] && kill "$spinner_pid" 2>/dev/null && wait "$spinner_pid" 2>/dev/null
    spinner_pid=""
    printf "\r\033[K"
}

# ─── Countdown ───────────────────────────────────────────────
countdown() {
    local WAIT_SECS="$1"
    local MSG="$2"
    for i in $(seq "$WAIT_SECS" -1 1); do
        printf "\r  ⏳ %s — %ds  " "$MSG" "$i"
        sleep 1
    done
    printf "\r\033[K"
}

# ─── Parse cooldown text ────────────────────────────────────
parse_cooldown() {
    local TEXT="$1"
    local MINS SECS
    MINS=$(echo "$TEXT" | grep -oP '\d+(?=m)' || echo 0)
    SECS=$(echo "$TEXT" | grep -oP '\d+(?=s)' || echo 0)
    [[ -z "$MINS" ]] && MINS=0
    [[ -z "$SECS" ]] && SECS=0
    echo $(( MINS * 60 + SECS + 5 ))
}

# ─── ค้นหา WordPress ─────────────────────────────────────────
declare -A _SEEN
DIRS=()

if [[ -n "$CPANEL_USERS" ]]; then
    log "🔍 Scan เฉพาะ: $CPANEL_USERS"
    start_spinner "Scanning WordPress installations..."
    for _usr in $CPANEL_USERS; do
        for _uhome in /home/$_usr /home2/$_usr /home3/$_usr /home4/$_usr /home5/$_usr; do
            [[ -d "$_uhome" ]] || continue
            while IFS= read -r -d '' _wpc; do
                _d="$(dirname "$_wpc")/"
                [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
            done < <(find "$_uhome" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
        done
    done
else
    start_spinner "Scanning WordPress installations..."
    if [[ -f /etc/trueuserdomains ]]; then
        while read -r _line; do
            _usr=$(echo "$_line" | awk '{print $2}' | tr -d ':')
            [[ -z "$_usr" || "$_usr" == "root" ]] && continue
            for _base in /home/$_usr /home2/$_usr /home3/$_usr /home4/$_usr /home5/$_usr; do
                [[ -d "$_base" ]] || continue
                while IFS= read -r -d '' _wpc; do
                    _d="$(dirname "$_wpc")/"
                    [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
                done < <(find "$_base" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
            done
        done < /etc/trueuserdomains
    fi
fi
stop_spinner

# ─── Filter ตาม domains.csv ─────────────────────────────────
declare -A MATCHED_DOMAINS
declare -A PARKED_INFO
PARKED_DOMAINS=()
NOT_ON_SERVER=()

if [[ $TARGET_DOMAIN_COUNT -gt 0 ]]; then
    FILTERED_DIRS=()
    for dir in "${DIRS[@]}"; do
        _folder=$(basename "${dir%/}")
        if [[ "$_folder" == "public_html" ]]; then
            _folder=$(basename "$(dirname "${dir%/}")")
        fi
        _folder=$(echo "$_folder" | tr '[:upper:]' '[:lower:]')
        if [[ -n "${TARGET_DOMAINS[$_folder]+_}" ]]; then
            FILTERED_DIRS+=("$dir")
            MATCHED_DOMAINS["$_folder"]=1
        fi
    done

    # Parked/Alias domains
    for _dom in "${!TARGET_DOMAINS[@]}"; do
        if [[ -z "${MATCHED_DOMAINS[$_dom]+_}" ]]; then
            _udd_line=$(grep "^${_dom}:" /etc/userdatadomains 2>/dev/null)
            if [[ -n "$_udd_line" ]]; then
                _udd_type=$(echo "$_udd_line" | awk -F'==' '{print $3}')
                _udd_main=$(echo "$_udd_line" | awk -F'==' '{print $4}')
                _udd_user=$(echo "$_udd_line" | cut -d: -f2 | awk -F'==' '{print $1}' | tr -d ' ')
                PARKED_DOMAINS+=("$_dom")
                PARKED_INFO["$_dom"]="${_udd_main}|${_udd_user}"
            else
                NOT_ON_SERVER+=("$_dom")
            fi
        fi
    done

    log "🎯 Filter domains.csv: ${#DIRS[@]} → ${#FILTERED_DIRS[@]} เว็บ"
    [[ ${#PARKED_DOMAINS[@]} -gt 0 ]] && log "🔗 Parked/Alias: ${#PARKED_DOMAINS[@]} เว็บ"
    [[ ${#NOT_ON_SERVER[@]} -gt 0 ]] && log "⚠️  ไม่อยู่บน server: ${#NOT_ON_SERVER[@]} เว็บ"
    DIRS=("${FILTERED_DIRS[@]}")
fi

TOTAL=${#DIRS[@]}
log "พบ WordPress  : $TOTAL เว็บ"
log "======================================"

# ─── Process ทีละเว็บ ────────────────────────────────────────
COUNT=0
SUCCESS=0
FAILED=0
SKIPPED=0

for dir in "${DIRS[@]}"; do
    COUNT=$((COUNT+1))

    CPUSER_NAME=$(echo "$dir" | sed 's|/home[0-9]*/||;s|/.*||')
    DOMAIN_NAME=$(basename "${dir%/}")
    [[ "$DOMAIN_NAME" == "public_html" ]] && DOMAIN_NAME=$(basename "$(dirname "${dir%/}")")
    LABEL="[$COUNT/$TOTAL] $CPUSER_NAME | $DOMAIN_NAME"

    # หา qc_email + api_key
    _qc_email="${DOMAIN_QC_EMAIL[$DOMAIN_NAME]:-}"
    _qc_key=""
    if [[ -n "$_qc_email" && -n "${QC_KEYS[$_qc_email]+_}" ]]; then
        _qc_key="${QC_KEYS[$_qc_email]}"
    fi

    # ถ้าไม่มี email/key → ใช้ตัวแรกใน QC_KEYS
    if [[ -z "$_qc_key" ]]; then
        for _fk in "${!QC_KEYS[@]}"; do
            _qc_email="$_fk"
            _qc_key="${QC_KEYS[$_fk]}"
            break
        done
    fi

    if [[ -z "$_qc_key" ]]; then
        log "⚠️ $LABEL | ไม่มี QC API key — ข้าม"
        SKIPPED=$((SKIPPED+1))
        continue
    fi

    # เช็ค LiteSpeed Cache active
    if ! wp --path="$dir" plugin is-active litespeed-cache --allow-root 2>/dev/null; then
        log "⏭  $LABEL | LiteSpeed ไม่ active"
        SKIPPED=$((SKIPPED+1))
        continue
    fi

    # ── Init ──────────────────────────────────────────────────
    INIT_R=$(timeout "$WP_TIMEOUT" wp --path="$dir" litespeed-online init \
        --allow-root 2>&1)

    if ! echo "$INIT_R" | grep -qi "success\|Congratulations\|already"; then
        log "❌ $LABEL | init fail: $(echo "$INIT_R" | tail -1 | head -c 80)"
        FAILED=$((FAILED+1))
        echo "$DOMAIN_NAME" >> "$LOG_FAIL"
        continue
    fi

    # ── Link (retry) ─────────────────────────────────────────
    LINK_OK=false
    ATTEMPT=0

    while [[ $ATTEMPT -lt $LINK_RETRY ]]; do
        ATTEMPT=$((ATTEMPT+1))

        LINK_R=$(timeout "$WP_TIMEOUT" wp --path="$dir" litespeed-online link \
            --email="$_qc_email" \
            --api-key="$_qc_key" \
            --allow-root 2>&1)

        if echo "$LINK_R" | grep -qi "success\|linked"; then
            LINK_OK=true
            break
        elif echo "$LINK_R" | grep -qi "try after"; then
            CD_TEXT=$(echo "$LINK_R" | grep -oP 'try after \K[^.]+')
            CD_SECS=$(parse_cooldown "$CD_TEXT")
            countdown "$CD_SECS" "$DOMAIN_NAME — rate limit"
        elif echo "$LINK_R" | grep -qi "Invalid API\|unauthorized"; then
            countdown 30 "$DOMAIN_NAME — API cooldown"
        elif echo "$LINK_R" | grep -qi "already"; then
            LINK_OK=true
            break
        else
            [[ $ATTEMPT -lt $LINK_RETRY ]] && countdown "$LINK_COOLDOWN" "$DOMAIN_NAME — retry"
        fi
    done

    if [[ "$LINK_OK" == true ]]; then
        log "✅ $LABEL | init ✅ | link ✅ (attempt $ATTEMPT/$LINK_RETRY)"
        SUCCESS=$((SUCCESS+1))
        echo "$DOMAIN_NAME" >> "$LOG_PASS"
    else
        log "❌ $LABEL | init ✅ | link ❌ (attempt $ATTEMPT/$LINK_RETRY)"
        FAILED=$((FAILED+1))
        echo "$DOMAIN_NAME" >> "$LOG_FAIL"
    fi

    # Cooldown ก่อนเว็บถัดไป
    [[ $COUNT -lt $TOTAL ]] && countdown "$LINK_COOLDOWN" "รอก่อนเว็บถัดไป"
done

echo ""
log "──────────────────────────────────────"
log "  ประมวลผลครบ $TOTAL เว็บ"

# ─── Parked domains: init + link ผ่าน main domain ────────────
PARKED_SUCCESS=0
PARKED_FAIL=0

if [[ ${#PARKED_DOMAINS[@]} -gt 0 ]]; then
    echo ""
    log "======================================"
    log "  🔗 Parked/Alias — Init + Link ผ่าน main domain"
    log "======================================"
    P_COUNT=0
    P_TOTAL=${#PARKED_DOMAINS[@]}
    declare -A MAIN_PROCESSED

    for _pd in "${PARKED_DOMAINS[@]}"; do
        P_COUNT=$((P_COUNT+1))

        _pd_info="${PARKED_INFO[$_pd]:-}"
        _pd_main=$(echo "$_pd_info" | cut -d'|' -f1)
        _pd_user=$(echo "$_pd_info" | cut -d'|' -f2)

        _pd_docroot=$(grep "^${_pd_main}:" /etc/userdatadomains 2>/dev/null | awk -F'==' '{print $5}')
        [[ -z "$_pd_docroot" ]] && _pd_docroot="/home/${_pd_user}/public_html"

        _pd_email="${DOMAIN_QC_EMAIL[$_pd]:-}"
        _pd_key=""
        if [[ -n "$_pd_email" && -n "${QC_KEYS[$_pd_email]+_}" ]]; then
            _pd_key="${QC_KEYS[$_pd_email]}"
        fi

        if [[ -z "$_pd_key" ]]; then
            log "  ⚠️ [$P_COUNT/$P_TOTAL] $_pd → ไม่มี QC API key — ข้าม"
            PARKED_FAIL=$((PARKED_FAIL+1))
            continue
        fi

        if [[ ! -f "$_pd_docroot/wp-config.php" ]]; then
            log "  ❌ [$P_COUNT/$P_TOTAL] $_pd → $_pd_main | ไม่เจอ WordPress"
            PARKED_FAIL=$((PARKED_FAIL+1))
            continue
        fi

        # Init + Link main domain (ครั้งเดียว)
        if [[ -z "${MAIN_PROCESSED[$_pd_main]+_}" ]]; then
            MAIN_PROCESSED["$_pd_main"]=1

            INIT_R=$(timeout "$WP_TIMEOUT" wp --path="$_pd_docroot" litespeed-online init \
                --allow-root 2>&1)

            if echo "$INIT_R" | grep -qi "success\|Congratulations\|already"; then
                # Link
                LINK_OK=false
                ATTEMPT=0
                while [[ $ATTEMPT -lt $LINK_RETRY ]]; do
                    ATTEMPT=$((ATTEMPT+1))
                    LINK_R=$(timeout "$WP_TIMEOUT" wp --path="$_pd_docroot" litespeed-online link \
                        --email="$_pd_email" \
                        --api-key="$_pd_key" \
                        --allow-root 2>&1)

                    if echo "$LINK_R" | grep -qi "success\|linked\|already"; then
                        LINK_OK=true
                        break
                    elif echo "$LINK_R" | grep -qi "try after"; then
                        CD_TEXT=$(echo "$LINK_R" | grep -oP 'try after \K[^.]+')
                        CD_SECS=$(parse_cooldown "$CD_TEXT")
                        countdown "$CD_SECS" "$_pd_main — rate limit"
                    else
                        [[ $ATTEMPT -lt $LINK_RETRY ]] && countdown "$LINK_COOLDOWN" "$_pd_main — retry"
                    fi
                done

                if [[ "$LINK_OK" == true ]]; then
                    log "  🔧 [$P_COUNT/$P_TOTAL] $_pd → main: $_pd_main | init ✅ | link ✅"
                else
                    log "  🔧 [$P_COUNT/$P_TOTAL] $_pd → main: $_pd_main | init ✅ | link ❌"
                fi
            else
                log "  🔧 [$P_COUNT/$P_TOTAL] $_pd → main: $_pd_main | init ❌"
            fi
        fi

        # Parked domain — log สำเร็จ (ใช้ link ของ main)
        log "  ✅ [$P_COUNT/$P_TOTAL] $_pd → $_pd_main ($_pd_user) | linked ผ่าน main"
        PARKED_SUCCESS=$((PARKED_SUCCESS+1))

        [[ $P_COUNT -lt $P_TOTAL ]] && countdown "$LINK_COOLDOWN" "รอก่อนเว็บถัดไป"
    done

    log "──────────────────────────────────────"
    log "  Parked เสร็จ $P_TOTAL เว็บ"
fi

# ─── Domain ไม่อยู่บน server ────────────────────────────────
if [[ ${#NOT_ON_SERVER[@]} -gt 0 ]]; then
    echo ""
    log "======================================"
    log "  ⚠️  Domain ไม่อยู่บน server นี้ ($(hostname))"
    log "======================================"
    for _ns in "${NOT_ON_SERVER[@]}"; do
        log "  ❌ $_ns — ไม่พบใน cPanel บน server นี้"
        echo "$_ns" >> "$LOG_FAIL"
    done
fi

# ─── สรุป ────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

log "======================================"
log " สรุปผลรวม  $VERSION"
log " รวมทั้งหมด      : $TOTAL เว็บ"
log " ✅ Init+Link     : $SUCCESS เว็บ"
log " ❌ Fail          : $FAILED เว็บ"
log " ⏭  Skip          : $SKIPPED เว็บ"
log " 🔗 Parked        : $PARKED_SUCCESS สำเร็จ / $PARKED_FAIL ไม่สำเร็จ"
if [[ ${#NOT_ON_SERVER[@]} -gt 0 ]]; then
log " ⚠️  ไม่อยู่บน server: ${#NOT_ON_SERVER[@]} เว็บ"
fi
log " เวลาที่ใช้       : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log "======================================"
log " Log รวม         : $LOG_FILE"
log " ✅ Pass          : $LOG_PASS"
log " ❌ Fail          : $LOG_FAIL"
log " ⏭  Skip          : $LOG_SKIP"
log "======================================"

# ─── Telegram Notification ───────────────────────────────────
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    HOSTNAME=$(hostname)
    TG_MSG="☁️ <b>QUIC.cloud Bulk Link — $HOSTNAME</b>

✅ Init+Link: $SUCCESS
❌ Fail: $FAILED
⏭ Skip: $SKIPPED
🔗 Parked: $PARKED_SUCCESS

⏱ $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"

    if [[ ${#NOT_ON_SERVER[@]} -gt 0 ]]; then
        TG_MSG="$TG_MSG

⚠️ <b>ไม่อยู่บน server:</b>
$(printf '  - %s\n' "${NOT_ON_SERVER[@]}")"
    fi

    TG_RESULT=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$TG_MSG" \
        -d parse_mode="HTML" 2>&1)

    if echo "$TG_RESULT" | grep -q '"ok":true'; then
        log "📨 Telegram notification sent"
    else
        log "⚠️  Telegram notification failed: $(echo "$TG_RESULT" | grep -o '"description":"[^"]*"' | head -1)"
    fi
fi

exit 0
