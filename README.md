# QUIC.cloud Bulk Init + Link

Bash script สำหรับ **Init + Link QUIC.cloud** ให้กับ WordPress ทุกเว็บบนเซิร์ฟเวอร์แบบ bulk ผ่าน **LiteSpeed Cache Plugin → QUIC.cloud**

รองรับหลาย QUIC.cloud Account (คนละ email คนละ api_key)

## คำสั่งรัน

```bash
curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/server-config.conf \
    -o /tmp/server-config.conf && \
curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/domains.csv \
    -o /tmp/domains.csv && \
bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/quiccloud-bulk-link.sh)
```

> ต้องรันด้วย **root**

---

## ไฟล์ในโปรเจค

| ไฟล์ | คำอธิบาย |
|------|----------|
| `quiccloud-bulk-link.sh` | Script หลัก |
| `server-config.conf` | QC credentials + Telegram + ตัวเลือก |
| `domains.csv` | domain + qc_email (ว่าง = ทุกเว็บ) |

## Config

### server-config.conf

```bash
# QUIC.cloud credentials (email → api_key)
declare -A QC_KEYS

QC_KEYS["ufavisionseoteam16@gmail.com"]="qc_api_key_1"
QC_KEYS["ufavisionseoteam17@gmail.com"]="qc_api_key_2"
QC_KEYS["ufavisionseoteam18@gmail.com"]="qc_api_key_3"

# cPanel Users (ว่าง = ทั้ง server)
CPANEL_USERS=""

# Telegram
TELEGRAM_BOT_TOKEN="xxxx:xxxxxxx"
TELEGRAM_CHAT_ID="-xxxxxxxxxx"

# ตัวเลือก
LINK_RETRY=5
LINK_COOLDOWN=3
```

### domains.csv

```csv
domain,qc_email
elon168.org,ufavisionseoteam18@gmail.com
kingdom988.com,ufavisionseoteam17@gmail.com
```

- มี domain → init + link เฉพาะ domain ที่ระบุ
- qc_email → ใช้ map หา api_key จาก QC_KEYS
- ว่าง / ไม่มีไฟล์ → init + link ทุกเว็บตาม CPANEL_USERS

---

## ขั้นตอนการทำงาน

| Step | ทำอะไร |
|------|--------|
| 1 | Scan WordPress ตาม CPANEL_USERS |
| 2 | Filter ตาม domains.csv (ถ้ามี) |
| 3 | ตรวจจับ Parked/Alias domain จาก /etc/userdatadomains |
| 4 | ทุก domain: `wp litespeed-online init` |
| 5 | ทุก domain: `wp litespeed-online link --email --api-key` |
| 6 | Rate limit → auto retry + cooldown |
| 7 | Parked domain → init + link ผ่าน main domain |
| 8 | สรุปผล + Telegram notification |

## Features

- **Multi-account** — QC_KEYS["email"]="api_key" per email
- **domains.csv** — ระบุ domain + qc_email เฉพาะ
- **Parked/Alias domain** — detect + init/link ผ่าน main domain
- **Not on server** — detect + log error
- **Retry + cooldown** — rate limit auto retry 5 ครั้ง
- **Telegram notification** — สรุปผลหลังรัน
- **Spinner** — แสดง progress
- **Log แยกตามสถานะ** — pass/fail/skip

## สถานะผลลัพธ์

| สถานะ | ความหมาย | Log File |
|-------|----------|----------|
| ✅ **Init+Link** | สำเร็จ | `quiccloud-bulk-link-pass.log` |
| ❌ **Fail** | init หรือ link ไม่สำเร็จ | `quiccloud-bulk-link-fail.log` |
| ⏭ **Skip** | Plugin ไม่ active / ไม่มี key | `quiccloud-bulk-link-skip.log` |

**Log:** `/var/log/quiccloud-bulk-link*.log`

## Workflow ร่วมกับ QuicCloud-Link-Checker

```
1. รัน check-quiccloud-link.sh (QuicCloud-Link-Checker repo)
   → เห็นเว็บที่ ANONYMOUS / NOT ACTIVATED

2. เอารายชื่อใส่ domains.csv

3. รัน quiccloud-bulk-link.sh (repo นี้)
   → init + link ให้ทุกเว็บ

4. รัน check อีกครั้ง → ทุกเว็บ LINKED ✅
```

## Changelog

### v1.0 (2026-04-28) — ปัจจุบัน

- Init + Link QUIC.cloud แบบ bulk
- Multi-account: QC_KEYS per email
- domains.csv: domain + qc_email
- Parked/Alias domain support
- Retry + cooldown
- Telegram notification

## License

MIT
