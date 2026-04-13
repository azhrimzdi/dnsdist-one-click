#!/bin/bash

# ============================================================
#  DNS Installer - dnsdist + blocklist setup
#  Author: auto-generated
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ============================================================
# Cek root
# ============================================================
if [ "$EUID" -ne 0 ]; then
  error "Jalankan script ini sebagai root (sudo)."
fi

# ============================================================
# STEP 1 - Install dnsdist
# ============================================================
info "Step 1: Menginstall dnsdist..."
apt install dnsdist -y || error "Gagal install dnsdist"
success "dnsdist berhasil diinstall."

# ============================================================
# STEP 2 - Install freecdb
# ============================================================
info "Step 2: Menginstall freecdb..."
apt install freecdb -y || error "Gagal install freecdb"
success "freecdb berhasil diinstall."

# ============================================================
# STEP 3 - Konfigurasi dnsdist.conf
# ============================================================
info "Step 3: Konfigurasi dnsdist..."
echo ""

# --- IP Server ---
read -rp "  Masukkan IP Server (contoh: 103.10.20.30): " IP_SERVER
while [[ -z "$IP_SERVER" ]]; do
  warn "IP Server tidak boleh kosong."
  read -rp "  Masukkan IP Server: " IP_SERVER
done

# --- IP Client ACL ---
read -rp "  Masukkan IP/Subnet Client untuk ACL (contoh: 192.168.1.0/24): " IP_CLIENT
while [[ -z "$IP_CLIENT" ]]; do
  warn "IP Client tidak boleh kosong."
  read -rp "  Masukkan IP/Subnet Client untuk ACL: " IP_CLIENT
done

# --- Pilihan mode blocklist action ---
echo ""
echo -e "  Pilih mode blocklist action:"
echo -e "  ${CYAN}[1]${NC} NXDOMAIN   - balas domain not found"
echo -e "  ${CYAN}[2]${NC} Web Server - redirect ke IP web server (block page)"
echo ""
read -rp "  Pilihan (1/2): " BLOCK_MODE
while [[ "$BLOCK_MODE" != "1" && "$BLOCK_MODE" != "2" ]]; do
  warn "Pilihan tidak valid. Masukkan 1 atau 2."
  read -rp "  Pilihan (1/2): " BLOCK_MODE
done

if [[ "$BLOCK_MODE" == "2" ]]; then
  read -rp "  Masukkan IP Web Server untuk redirect (contoh: 103.10.20.31): " IP_WEB_SERVER
  while [[ -z "$IP_WEB_SERVER" ]]; do
    warn "IP Web Server tidak boleh kosong."
    read -rp "  Masukkan IP Web Server: " IP_WEB_SERVER
  done
  BLOCK_ACTION="SpoofAction(\"${IP_WEB_SERVER}\")"
  BLOCK_LABEL="Web Server (redirect ke ${IP_WEB_SERVER})"
else
  BLOCK_ACTION="RCodeAction(DNSRCode.NXDOMAIN)"
  BLOCK_LABEL="NXDOMAIN"
fi

# --- Generate console key ---
info "Generating console key..."
CONSOLE_KEY=$(openssl rand -base64 32)
success "Console key berhasil dibuat."

# --- Backup config lama ---
CONF_FILE="/etc/dnsdist/dnsdist.conf"
if [ -f "$CONF_FILE" ]; then
  BACKUP_FILE="${CONF_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  info "Backup config lama ke: $BACKUP_FILE"
  cp "$CONF_FILE" "$BACKUP_FILE"
fi

# --- Tulis config baru ---
info "Menulis config baru ke $CONF_FILE..."
cat > "$CONF_FILE" <<EOF
-- listen DNS
setLocal("${IP_SERVER}:53", {reusePort=true})

-- console access
setKey("${CONSOLE_KEY}")
controlSocket("127.0.0.1:5199")

-- ring buffer
setRingBuffersSize(1000000)

-- performance tuning
setMaxUDPOutstanding(65535)
setMaxTCPClientThreads(100)
setMaxTCPQueuedConnections(2000)
setMaxTCPConnectionsPerClient(20)

-- backend recursor
newServer({ address="1.1.1.1:53", name="cf-1", checkName="cloudflare.com.", mustResolve=true })
newServer({address="9.9.9.9:53",name="quad", pool="", mustResolve=true})
setServerPolicy(leastOutstanding)

-- packet cache
pc = newPacketCache(10000000)
getPool(""):setCache(pc)

-- load blocklist
local blocklistKVS = newCDBKVStore("/opt/blocklist/domains.cdb", 60)

-- wireFormat = false karena key di CDB adalah plain text
local qnameLookupKey = KeyValueLookupKeyQName(false)
local suffixLookupKey = KeyValueLookupKeySuffix(2, false)

addAction(
    KeyValueStoreLookupRule(blocklistKVS, suffixLookupKey),
    ${BLOCK_ACTION}
)

-- rate limit
addAction(MaxQPSIPRule(10000), DropAction())

-- forward normal DNS
addAction(AllRule(), PoolAction(""))

-- disable security polling
setSecurityPollSuffix("")

-- ACL
setACL({
"127.0.0.0/8",
"${IP_CLIENT}"
})
EOF

success "Config dnsdist berhasil ditulis."

# ============================================================
# STEP 4 - Buat folder /opt/blocklist
# ============================================================
info "Step 4: Membuat folder /opt/blocklist..."
mkdir -p /opt/blocklist
success "Folder /opt/blocklist berhasil dibuat."

# ============================================================
# STEP 5 - Buat file sources.txt
# ============================================================
info "Step 5: Membuat /opt/blocklist/sources.txt..."
cat > /opt/blocklist/sources.txt <<'SRCEOF'
https://trustpositif.komdigi.go.id/assets/db/domains_isp
https://trustpositif.komdigi.go.id/assets/db/ipaddress_isp
SRCEOF
success "sources.txt berhasil dibuat."

# ============================================================
# STEP 6 - Buat file update-blocklist.sh
# ============================================================
info "Step 6: Membuat /opt/blocklist/update-blocklist.sh..."
cat > /opt/blocklist/update-blocklist.sh <<'SCRIPTEOF'
#!/bin/bash

WORKDIR="/opt/blocklist"
SOURCE="$WORKDIR/sources.txt"

RAW="$WORKDIR/raw.tmp"
NEW="$WORKDIR/new_domains.tmp"
FINAL="$WORKDIR/domains.txt"
TMP="$WORKDIR/domains.tmp"

CDB_INPUT="$WORKDIR/domains.input"
CDB_FILE="$WORKDIR/domains.cdb"
CDB_TMP="$WORKDIR/domains.cdb.tmp"

LOG="$WORKDIR/update.log"

echo "===== Updating DNS Blocklist =====" | tee -a "$LOG"
date | tee -a "$LOG"

rm -f "$RAW" "$NEW" "$TMP" "$CDB_INPUT" "$CDB_TMP"

# =============================
# DOWNLOAD SOURCES
# =============================

while read url
do
  [[ -z "$url" || "$url" =~ ^# ]] && continue

  echo "Downloading $url" | tee -a "$LOG"

  curl -L \
    --retry 3 \
    --retry-delay 5 \
    --connect-timeout 10 \
    --max-time 120 \
    -s "$url" >> "$RAW"

done < "$SOURCE"

if [ ! -s "$RAW" ]; then
  echo "Download failed, keeping old blocklist" | tee -a "$LOG"
  exit 1
fi

if grep -qi "<html" "$RAW"; then
  echo "Downloaded HTML instead of blocklist, aborting" | tee -a "$LOG"
  exit 1
fi

echo "Extracting domains..." | tee -a "$LOG"

# =============================
# EXTRACT DOMAIN
# =============================

grep -Eo '([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$RAW" \
| sed 's/^\.//' \
| tr '[:upper:]' '[:lower:]' \
| sort -u > "$NEW"

NEWCOUNT=$(wc -l < "$NEW")

echo "New domains extracted: $NEWCOUNT" | tee -a "$LOG"

if [ "$NEWCOUNT" -lt 1000 ]; then
  echo "Blocklist suspiciously small, aborting update" | tee -a "$LOG"
  exit 1
fi

# =============================
# REPLACE BLOCKLIST
# =============================

echo "Replacing old blocklist..." | tee -a "$LOG"

mv "$NEW" "$TMP"

TOTAL=$(wc -l < "$TMP")
echo "Total domains in new blocklist: $TOTAL" | tee -a "$LOG"

mv "$TMP" "$FINAL"

# =============================
# CONVERT TO CDB
# =============================

echo "Converting to CDB format..." | tee -a "$LOG"

awk '{ print "+" length($0) ",1:" $0 "->1" } END { print "" }' "$FINAL" > "$CDB_INPUT"

echo "Building CDB file..." | tee -a "$LOG"

cdbmake "$CDB_TMP" "$WORKDIR/cdbmake.tmp" < "$CDB_INPUT"

if [ ! -s "$CDB_TMP" ]; then
  echo "CDB build failed, aborting" | tee -a "$LOG"
  exit 1
fi

mv "$CDB_TMP" "$CDB_FILE"

echo "CDB build completed" | tee -a "$LOG"

# =============================
# RELOAD DNSDIST
# =============================

echo "Reloading dnsdist..." | tee -a "$LOG"

dnsdist -c -e "reloadConfig"

echo "Update completed successfully" | tee -a "$LOG"
SCRIPTEOF

chmod +x /opt/blocklist/update-blocklist.sh
success "update-blocklist.sh berhasil dibuat dan diberi izin eksekusi."

# ============================================================
# STEP 7 - Restart dnsdist & Test dig
# ============================================================
info "Step 7: Merestart dnsdist..."
systemctl restart dnsdist || warn "Gagal restart dnsdist, cek config manual."
sleep 2

info "Testing DNS dengan dig ke google.com..."
DIG_RESULT=$(dig @"${IP_SERVER}" google.com +short 2>&1)

if [[ -z "$DIG_RESULT" ]]; then
  warn "dig tidak mengembalikan hasil. Pastikan dnsdist berjalan dan firewall port 53 terbuka."
else
  success "DNS merespon untuk google.com:"
  echo "  $DIG_RESULT"
fi

# ============================================================
# STEP 8 - Notifikasi Selesai
# ============================================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   DNS dnsdist BERHASIL DIINSTALL!        ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  ${CYAN}IP Server      :${NC} ${IP_SERVER}"
echo -e "  ${CYAN}IP Client ACL  :${NC} ${IP_CLIENT}"
echo -e "  ${CYAN}Blocklist Mode :${NC} ${BLOCK_LABEL}"
echo -e "  ${CYAN}Console Key    :${NC} ${CONSOLE_KEY}"
echo -e "  ${CYAN}Config File    :${NC} ${CONF_FILE}"
echo -e "  ${CYAN}Blocklist Dir  :${NC} /opt/blocklist"
echo ""
echo -e "  Untuk update blocklist, jalankan:"
echo -e "  ${YELLOW}bash /opt/blocklist/update-blocklist.sh${NC}"
echo ""