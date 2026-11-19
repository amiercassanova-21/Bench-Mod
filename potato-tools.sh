#!/bin/bash
# =====================================================
#  POTATO TOOLS - pemasang perintah tambahan untuk VPS Potato
#  Pakai (sebagai root):
#    bash <(curl -fsSL https://raw.githubusercontent.com/amiercassanova-21/Bench-Mod/main/potato-tools.sh)
#  Hanya MEMASANG perintah; tidak ada yang dijalankan otomatis.
#  Aman diulang (untuk update): file perintah ditimpa versi terbaru.
#  Daftar perintah setelah terpasang: potatocmd
# =====================================================
G='\e[32m'; R='\e[31m'; Y='\e[33m'; C='\e[36m'; N='\e[0m'
[[ $EUID -eq 0 ]] || { echo -e "${R}Jalankan sebagai root.${N}"; exit 1; }
[[ -f /usr/sbin/potatonc/potato.db ]] || { echo -e "${R}Ini bukan VPS Potato (/usr/sbin/potatonc/potato.db tidak ada). Dibatalkan.${N}"; exit 1; }
command -v python3 >/dev/null 2>&1 || echo -e "${Y}python3 tidak ada: perintah 'cek' tidak akan jalan.${N}"
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo -e "${C}Memasang sqlite3 (dipakai bersihrecovery & cekvps)...${N}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sqlite3 >/dev/null 2>&1 \
    || { apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sqlite3 >/dev/null 2>&1; }
  command -v sqlite3 >/dev/null 2>&1 && echo -e "${G}sqlite3 terpasang.${N}" || echo -e "${Y}sqlite3 gagal dipasang; bersihrecovery & jumlah akun di cekvps tidak jalan.${N}"
fi
echo -e "${C}Memasang perintah...${N}"

# ---------- cek : cari akun di semua protokol (baca-saja) ----------
cat > /usr/local/bin/cek <<'EOF'
#!/usr/bin/env python3
# cek <nama/uuid/password> : cari akun di SEMUA protokol Potato (baca-saja).
# Sumber: /usr/sbin/potatonc/potato.db (SQLite), dibuka mode read-only.
import sqlite3, sys, time, datetime

DB = '/usr/sbin/potatonc/potato.db'
R, G, Y, C, W, D, N = '\033[31m', '\033[32m', '\033[33m', '\033[36m', '\033[1;97m', '\033[2m', '\033[0m'
LN = '─' * 42
TABEL = [('VLESS', 'account_vlesses', 'uuid'), ('VMESS', 'account_vmesses', 'uuid'),
         ('TROJAN', 'account_trojans', 'uuid'), ('SSH', 'account_sshs', 'password')]

q = ' '.join(sys.argv[1:]).strip()
if not q:
    print(f" Pakai : {C}cek <nama>{N}")
    print(f" Contoh: {C}cek budi{N}   {C}cek <uuid>{N}")
    sys.exit(1)

try:
    con = sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=5)
    con.row_factory = sqlite3.Row
except Exception as e:
    print(f" {R}Database Potato tidak bisa dibuka: {e}{N}"); sys.exit(1)

now = int(time.time()); today = datetime.date.today()

def sisa(exp):
    try: d = (datetime.date.fromisoformat(exp) - today).days
    except Exception: return '-'
    if d >= 20000: return 'Lifetime'
    if d > 0: return f'sisa {d} hari'
    if d == 0: return 'habis hari ini'
    return f'lewat {-d} hari'

def status(r):
    if r['status'] == 'RECOVERY': return f"{D}🗑 DI RECOVERY{N} (sudah dihapus)"
    if r['status_lock'] == 'LOCK': return f"{R}🔒 DIKUNCI{N}"
    if (r['at_banned'] or 0) > now:
        return f"{R}⛔ DIBAN (Limit IP){N}, terbuka {time.strftime('%H:%M', time.localtime(r['at_banned']))}"
    if (r['date_exp'] or '') < today.isoformat(): return f"{R}✖ EXPIRED{N}"
    return f"{G}✔ AKTIF{N}"

def cari(exact):
    hasil = []
    for nama, t, kunci in TABEL:
        try:
            if exact:
                sql = f"select * from {t} where lower(username)=lower(?) or {kunci}=?"; arg = (q, q)
            else:
                sql = f"select * from {t} where lower(username) like lower(?)"; arg = (f'%{q}%',)
            for r in con.execute(sql + " order by lower(username)", arg): hasil.append((nama, r))
        except sqlite3.Error:
            pass
    return hasil

hasil = cari(True)
if not hasil:
    mirip = cari(False)
    if not mirip:
        print(f" {R}Akun '{q}' tidak ditemukan di VLESS / VMESS / TROJAN / SSH{N}"); sys.exit(1)
    nama_mirip = sorted({r['username'].lower(): r['username'] for _, r in mirip}.values(), key=str.lower)[:15]
    print(f" {Y}Tidak ada yang persis '{q}'. Yang mirip:{N}")
    for u in nama_mirip: print(f"   {C}cek {u}{N}")
    sys.exit(1)

print(LN)
for nama, r in hasil:
    trial = r['type'] != 'NORMAL' or (r['at_trial'] or 0) > 0
    print(f" {W}{nama}{N}{'  ' + Y + '(trial)' + N if trial else ''}")
    print(f"   {'Username':<11} : {r['username']}")
    print(f"   {'Expired':<11} : {Y}{r['date_exp']}{N}  ({sisa(r['date_exp'])})")
    print(f"   {'Status':<11} : {status(r)}")
    lim = r['limit_ip'] or 0
    print(f"   {'Limit IP':<11} : {'Unlimited' if lim == 0 else lim}")
    if nama != 'SSH' or (r['max_bw'] or 0) > 0:
        mx = 'Unlimited' if (r['max_bw'] or 0) == 0 else r['max_bw_hum']
        print(f"   {'Kuota':<11} : {r['use_bw_hum']} / {mx}")
    print(LN)
EOF
chmod +x /usr/local/bin/cek

# ---------- bersihrecovery : hapus akun RECOVERY lama (backup + konfirmasi y/t) ----------
cat > /usr/local/sbin/bersihrecovery <<'EOF'
#!/bin/bash
# bersihrecovery [bulan]  — hapus akun RECOVERY Potato yang expired > N bulan (default 4)
DB=/usr/sbin/potatonc/potato.db
MONTHS="${1:-4}"
command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 belum terpasang di VPS ini."; exit 1; }
[ -f "$DB" ] || { echo "potato.db tidak ditemukan: $DB"; exit 1; }
[[ "$MONTHS" =~ ^[0-9]+$ ]] || { echo "Jumlah bulan harus angka. Contoh: bersihrecovery 3"; exit 1; }
CUT=$(sqlite3 "$DB" "SELECT date('now','-$MONTHS months');")
echo "== BERSIH RECOVERY POTATO =="
echo "Target: akun RECOVERY yang expired sebelum $CUT (lebih dari $MONTHS bulan)"
echo
tot=0
for t in account_vlesses account_vmesses account_trojans account_sshs; do
  n=$(sqlite3 "$DB" "SELECT count(*) FROM $t WHERE status='RECOVERY' AND date_exp < date('now','-$MONTHS months');" 2>/dev/null); n=${n:-0}
  printf "  %-18s : %s\n" "$t" "$n"; tot=$((tot+n))
done
echo "  ------------------------------"
printf "  %-18s : %s\n" "TOTAL akan dihapus" "$tot"
echo
[ "$tot" -eq 0 ] && { echo "Tidak ada recovery lama. Sudah bersih."; exit 0; }
read -rp "Lanjut hapus $tot akun recovery ini? (y/t) : " y
[[ "$y" == y || "$y" == Y ]] || { echo "Dibatalkan, tidak ada yang dihapus."; exit 0; }
BK=/root/potato.db.bak-$(date +%F_%H%M%S)
cp -a "$DB" "$BK" && echo "Backup dibuat: $BK"
for t in account_vlesses account_vmesses account_trojans account_sshs; do
  sqlite3 "$DB" "DELETE FROM $t WHERE status='RECOVERY' AND date_exp < date('now','-$MONTHS months');"
done
sqlite3 "$DB" "VACUUM;"
echo
echo "SELESAI. Sisa recovery sekarang:"
for t in account_vlesses account_vmesses account_trojans account_sshs; do
  printf "  %-18s : %s\n" "$t" "$(sqlite3 "$DB" "SELECT count(*) FROM $t WHERE status='RECOVERY';")"
done
echo
echo "Kalau perlu batalkan: cp -a $BK $DB"
EOF
chmod +x /usr/local/sbin/bersihrecovery && echo "bersihrecovery dibuat."

# ---------- cekbeban : beban & kapasitas VPS (baca-saja) ----------
if [ -e /usr/local/sbin/cekbeban ] && ! grep -q 'versi umum / Potato' /usr/local/sbin/cekbeban; then echo 'cekbeban sudah ada di VPS ini (bukan versi kita) - dibatalkan.'; else
cat > /usr/local/sbin/cekbeban <<'CBEOF'
#!/bin/bash
# cekbeban (versi umum / Potato) : cek beban & kapasitas VPS + saran.
# HANYA MEMBACA, tidak mengubah apa pun. "cekbeban live" = segarkan tiap 5 detik.
R='\e[31m'; G='\e[32m'; Y='\e[33m'; C='\e[36m'; B='\e[34m'; W='\e[1;97m'; D='\e[2m'; N='\e[0m'
LN="──────────────────────────────────────────"
num(){ [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }
bar(){ local p=$1 w=16 f i s=""; (( p<0 ))&&p=0; f=$(( p*w/100 )); (( f>w ))&&f=w
  for((i=0;i<w;i++)); do ((i<f))&&s+="█"||s+="░"; done; echo "$s"; }
lv(){ if (( $1>=$3 )); then ST_C=$R; ST_T="BAHAYA"; return 2
      elif (( $1>=$2 )); then ST_C=$Y; ST_T="WASPADA"; return 1
      else ST_C=$G; ST_T="AMAN"; return 0; fi; }
row(){ lv "$2" "$3" "$4"; local r=$?
  printf "  ${W}%-10s${N} ${ST_C}%s %3s%% %s${N}\n" "$1" "$(bar "$2")" "$2" "$ST_T"
  printf "    ${D}%s${N}\n" "$5"; return $r; }
# nama proses pemilik port LISTEN; "tersembunyi" bila socket ada tapi prosesnya tak terlihat
owner(){ local ino fd pid nm
  nm=$(ss -Hltnp "sport = :$1" 2>/dev/null | grep -o 'users:(("[^"]*' | head -n1 | cut -d'"' -f2)
  [[ -n "$nm" ]] && { echo "$nm"; return; }
  ino=$(ss -Hltne "sport = :$1" 2>/dev/null | grep -o 'ino:[0-9]*' | head -n1 | cut -d: -f2)
  [[ -z "$ino" || "$ino" == 0 ]] && { echo "-"; return; }
  fd=$(find /proc/[0-9]*/fd -lname "socket:\[$ino\]" 2>/dev/null | head -n1); pid=$(cut -d/ -f3 <<< "$fd")
  [[ -n "$pid" ]] && cat /proc/$pid/comm 2>/dev/null || echo "tersembunyi"; }
render(){
  local L1 L5 CORE CPUP IOWP STP MT MU RAMP EST TW PLO PHI PR TOPN TOPP PORTP CTC CTM CTP FRONT CLI CAP USE FP since E1 E2 E3 E4 LOGS s1 s2
  local -a SARAN=()
  read -r L1 L5 _ < /proc/loadavg; CORE=$(nproc)
  s1=$(head -n1 /proc/stat); sleep 2; s2=$(head -n1 /proc/stat)
  read -r CPUP IOWP STP < <(awk -v a="$s1" -v b="$s2" 'BEGIN{ split(a,x," "); split(b,y," ")
    for(i=2;i<=9;i++){ d[i]=y[i]-x[i]; t+=d[i] }; if(t<=0) t=1
    printf "%d %d %d", (d[2]+d[3]+d[4]+d[7]+d[8])*100/t, d[6]*100/t, d[9]*100/t }')
  CPUP=$(num "$CPUP"); IOWP=$(num "$IOWP"); STP=$(num "$STP")
  read -r MT MU < <(free -m | awk '/^Mem:/{print $2,$3}'); MT=$(num "$MT"); MU=$(num "$MU"); (( MT>0 )) && RAMP=$(( MU*100/MT )) || RAMP=0
  EST=$(ss -Htn state established 2>/dev/null | wc -l); TW=$(ss -Htn state time-wait 2>/dev/null | wc -l)
  read -r PLO PHI < /proc/sys/net/ipv4/ip_local_port_range; PR=$(( PHI-PLO+1 ))
  # port lokal: koneksi internal 127.0.0.1 -> backend, dikelompokkan per port tujuan.
  # Backend terpadat yang menentukan (tiap backend punya jatah port lokal sendiri).
  read -r TOPN TOPP < <(ss -Htn state established 2>/dev/null | awk '{n=0; for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) ad[++n]=$i
    if(n>=2 && ad[1] ~ /^127\.0\.0\.1:/ && ad[2] ~ /^127\.0\.0\.1:/){split(ad[2],a,":"); c[a[2]]++}}
    END{m=0; p="-"; for(k in c) if(c[k]>m){m=c[k]; p=k}; print m+0, p}')
  TOPN=$(num "$TOPN"); PORTP=$(( (TOPN+TW)*100/PR )); (( PORTP>100 )) && PORTP=100
  CTC=$(num "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)"); CTM=$(num "$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)")
  (( CTM>0 )) && CTP=$(( CTC*100/CTM )) || CTP=-1
  # siapa yang menerima pelanggan di port 443
  FRONT=$(owner 443); local BOWN="-"; [[ "$TOPP" =~ ^[0-9]+$ ]] && BOWN=$(owner "$TOPP")
  CLI=$(ss -Htn state established '( sport = :443 or sport = :80 )' 2>/dev/null | wc -l)
  CAP=0; USE=0
  case "$FRONT" in
    nginx)   local WK WC; WK=$(ps -eo args= | grep -cx 'nginx: worker process')
             WC=$(num "$(sed -nE 's/^[[:space:]]*worker_connections[[:space:]]+([0-9]+);.*/\1/p' /etc/nginx/nginx.conf 2>/dev/null | head -n1)")
             CAP=$(( WK*WC )); USE=$(( CLI*2 )); FP="$USE / $CAP slot ($WK worker x $WC)" ;;
    haproxy) CAP=$(num "$(awk '/^global/{g=1;next} /^[a-z]/{g=0} g&&$1=="maxconn"{print $2; exit}' /etc/haproxy/haproxy.cfg 2>/dev/null)")
             USE=$CLI; FP="$USE / $CAP koneksi (maxconn haproxy)" ;;
  esac
  since=$(date -d '-60 min' '+%F %T')
  local since2; since2=$(date -d '-60 min' '+%Y/%m/%d %H:%M:%S')
  LOGS=$( { journalctl -p warning --since "$since" --no-pager -q 2>/dev/null | tail -n 20000
            # log nginx & xray berformat "YYYY/MM/DD HH:MM:SS" -> ambil 1 jam terakhir saja
            for f in /var/log/nginx/error.log /var/log/xray/error.log; do
              [[ -f $f ]] && tail -n 50000 "$f" | awk -v s="$since2" 'substr($0,1,19)>=s'; done; } )
  E1=$(num "$(grep -ci 'worker_connections are not enough' <<< "$LOGS")")
  E2=$(num "$(grep -ci 'too many open files' <<< "$LOGS")")
  E3=$(num "$(grep -ci 'cannot assign requested address' <<< "$LOGS")")
  E4=$(num "$(journalctl -k --since "$since" --no-pager -q 2>/dev/null | grep -ci 'table full')")

  clear 2>/dev/null
  echo -e "${B}┌${LN}${N}"
  echo -e "${B}│${N} ${W}CEK BEBAN VPS${N}  ·  ${C}$(date '+%d-%m-%Y %H:%M:%S')${N}"
  echo -e "${B}│${N} ${C}$(hostname)${N}  ·  port 443: ${C}$FRONT${N}"
  echo -e "${B}└${LN}${N}"
  echo
  local STX=""; (( STP>=10 && STP<20 )) && STX=" (pantau)"
  row "CPU" "$CPUP" 70 90 "$CORE core · load $L5 · iowait $IOWP% · steal $STP%$STX"; (( $? )) && SARAN+=("CPU|$ST_T")
  (( IOWP>=20 )) && SARAN+=("IOW|WASPADA"); (( STP>=20 )) && SARAN+=("STEAL|WASPADA")   # 10-19% cukup ditandai "pantau" (lonjakan sesaat wajar)
  row "RAM" "$RAMP" 80 90 "$MU / $MT MB terpakai"; (( $? )) && SARAN+=("RAM|$ST_T")
  row "Port lokal" "$PORTP" 60 85 "ke $BOWN (port $TOPP): $TOPN + TIME_WAIT $TW / $PR"; (( $? )) && SARAN+=("PORT|$ST_T")
  if (( CTP>=0 )); then row "Conntrack" "$CTP" 70 90 "$CTC / $CTM catatan koneksi"; (( $? )) && SARAN+=("CT|$ST_T"); fi
  if (( CAP>0 )); then
    local FPP=$(( USE*100/CAP )); (( FPP>100 )) && FPP=100
    row "${FRONT^}" "$FPP" 70 90 "$FP"; (( $? )) && SARAN+=("FRONT|$ST_T")
  fi
  echo
  echo -e "  ${W}Koneksi aktif total${N} : ${C}$EST${N}  ${D}(pelanggan di 80/443: $CLI)${N}"
  echo
  echo -e "  ${W}Tanda bahaya${N} ${D}(1 jam terakhir, harus 0)${N}"
  for t in "$E1|Koneksi ditolak (slot penuh)" "$E2|File terbuka habis" "$E3|Port lokal habis" "$E4|Tabel conntrack penuh"; do
    n=${t%%|*}; (( n>0 )) && printf "   ${R}✖ %-5s${N} %s\n" "$n" "${t#*|}" || printf "   ${G}✔ %-5s${N} %s\n" "$n" "${t#*|}"
  done
  (( E1>0 )) && SARAN+=("E1|BAHAYA"); (( E2>0 )) && SARAN+=("E2|BAHAYA"); (( E3>0 )) && SARAN+=("PORT|BAHAYA"); (( E4>0 )) && SARAN+=("CT|BAHAYA")
  echo; echo -e "${B}${LN}${N}"
  if (( ${#SARAN[@]} == 0 )); then echo -e "  ${G}✔ SEMUA AMAN${N} · tidak perlu tindakan."
  else
    echo -e "  ${Y}YANG PERLU DILAKUKAN:${N}"
    local s k seen=" "
    for s in "${SARAN[@]}"; do k=${s%%|*}; [[ "$seen" == *" $k "* ]] && continue; seen+="$k "
      case $k in
        CPU)   echo -e "  ${Y}•${N} ${W}CPU ${s#*|}${N}"
               echo -e "    Sering penuh saat ramai? Naikkan VPS ke"
               echo -e "    core lebih banyak, atau bagi pelanggan" ; echo -e "    ke VPS lain." ;;
        IOW)   echo -e "  ${Y}•${N} ${W}Disk lambat (iowait $IOWP%)${N}"
               echo -e "    Cek log besar:"; echo -e "    ${C}du -sh /var/log/* | sort -h | tail -5${N}" ;;
        STEAL) echo -e "  ${Y}•${N} ${W}CPU diambil VPS lain (steal $STP%)${N}"
               echo -e "    Server penyedia sedang padat. Kalau ini"
               echo -e "    sering terjadi tiap malam, pertimbangkan"
               echo -e "    pindah region atau paket CPU dedicated." ;;
        RAM)   echo -e "  ${Y}•${N} ${W}RAM ${s#*|}${N}"
               echo -e "    Tambah RAM VPS, atau restart xray saat sepi:"; echo -e "    ${C}systemctl restart xray${N}" ;;
        PORT)  echo -e "  ${Y}•${N} ${W}Port lokal ${s#*|}${N}"
               echo -e "    Aktifkan pemakaian ulang port:"; echo -e "    ${C}sysctl -w net.ipv4.tcp_tw_reuse=1${N}" ;;
        CT)    echo -e "  ${Y}•${N} ${W}Conntrack ${s#*|}${N}"
               echo -e "    Naikkan batasnya:"; echo -e "    ${C}sysctl -w net.netfilter.nf_conntrack_max=524288${N}" ;;
        FRONT) echo -e "  ${Y}•${N} ${W}${FRONT^} ${s#*|}${N}"
               echo -e "    Batas koneksi $FRONT hampir habis. Naikkan"; echo -e "    batasnya atau bagi pelanggan ke VPS lain." ;;
        E1)    echo -e "  ${R}•${N} ${W}Ada koneksi DITOLAK${N}"
               echo -e "    Batas slot penuh. Naikkan worker_connections"; echo -e "    / maxconn, lalu reload." ;;
        E2)    echo -e "  ${R}•${N} ${W}File terbuka habis${N}"
               echo -e "    Naikkan LimitNOFILE service lalu restart." ;;
      esac
    done
  fi
  echo -e "${B}${LN}${N}"
  echo -e "  ${D}Hijau aman · Kuning waspada · Merah bahaya${N}"
}
if [[ "$1" == live ]]; then trap 'echo; exit 0' INT
  while true; do render; echo -e "  ${D}Live tiap 5 detik · Ctrl-C keluar${N}"; sleep 5; done
else render; fi
CBEOF
chmod +x /usr/local/sbin/cekbeban && echo 'cekbeban terpasang. Jalankan: cekbeban'; fi

# ---------- cekvps : ringkasan VPS + jumlah akun (baca-saja) ----------
cat > /usr/local/sbin/cekvps <<'CEKVPS_EOF'
#!/bin/bash
# cekvps mandiri untuk VPS Potato (tanpa install paket apa pun)
R='\e[31m';G='\e[32m';Y='\e[33m';B='\e[34m';C='\e[36m';W='\e[1;97m';N='\e[0m'
IN="────────────────────────────────────"
PDB=/usr/sbin/potatonc/potato.db
num(){ [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }
bar(){ local p w=14 f i s=""; p=$(num "$1"); f=$((p*w/100)); ((f>w))&&f=w; ((f<0))&&f=0
  for((i=0;i<w;i++)); do ((i<f))&&s="${s}#"||s="${s}."; done; echo "$s"; }
clr(){ local p; p=$(num "$1"); ((p>=90))&&{ echo "$R";return;}; ((p>=70))&&{ echo "$Y";return;}; echo "$G"; }
hb(){ numfmt --to=iec --suffix=B/s "$1" 2>/dev/null||echo "${1}B/s"; }
# .timeout: tunggu s/d 2 detik bila database Potato sedang dipakai (dulu langsung "-")
pcount(){ local v; command -v sqlite3 >/dev/null 2>&1 && [ -f "$PDB" ] && v=$(sqlite3 "$PDB" ".timeout 2000" "SELECT count(*) FROM $1" 2>/dev/null); [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo "-"; }
render(){
  local a1 b1 c1 d1 e1 f1 g1 h1 a2 b2 c2 d2 e2 f2 g2 h2
  read -r _ a1 b1 c1 d1 e1 f1 g1 h1 _ </proc/stat; local T1=$((a1+b1+c1+d1+e1+f1+g1+h1)) I1=$((d1+e1))
  sleep 0.4
  read -r _ a2 b2 c2 d2 e2 f2 g2 h2 _ </proc/stat; local T2=$((a2+b2+c2+d2+e2+f2+g2+h2)) I2=$((d2+e2))
  local DT=$((T2-T1)); ((DT<=0))&&DT=1; local CPU=$(((100*(DT-(I2-I1)))/DT)) CORE=$(nproc)
  local LAV=$(cut -d' ' -f1-3 /proc/loadavg)
  local MT MU MP ST SU SP
  read MT MU < <(free -m|awk '/^Mem:/{print $2,$3}'); MT=$(num "$MT"); MU=$(num "$MU"); MP=0; ((MT>0))&&MP=$((MU*100/MT))
  read ST SU < <(free -m|awk '/^Swap:/{print $2,$3}'); ST=$(num "$ST"); SU=$(num "$SU"); SP=0; ((ST>0))&&SP=$((SU*100/ST))
  local DU DTT DP; DU=$(df -h /|awk 'NR==2{print $3}'); DTT=$(df -h /|awk 'NR==2{print $2}'); DP=$(num "$(df /|awk 'NR==2{gsub("%","",$5);print $5}')")
  local UPT=$(uptime -p 2>/dev/null|sed 's/^up //'); [[ -z "$UPT" ]] && UPT=$(uptime|awk -F, '{print $1}')
  local IF=$(ip route 2>/dev/null|awk '/^default/{print $5;exit}'); IF=${IF:-eth0}
  local RX1=$(cat /sys/class/net/$IF/statistics/rx_bytes 2>/dev/null||echo 0) TX1=$(cat /sys/class/net/$IF/statistics/tx_bytes 2>/dev/null||echo 0)
  sleep 1
  local RX2=$(cat /sys/class/net/$IF/statistics/rx_bytes 2>/dev/null||echo 0) TX2=$(cat /sys/class/net/$IF/statistics/tx_bytes 2>/dev/null||echo 0)
  local DL=$(hb $((RX2-RX1))) UL=$(hb $((TX2-TX1)))
  local CON=$(ss -tun state established 2>/dev/null|grep -c .)
  local AV=$(pcount account_vlesses) AM=$(pcount account_vmesses) AT=$(pcount account_trojans) AS=$(pcount account_sshs)
  # jumlahkan yang berupa angka saja (dulu "-" ikut dihitung -> error & mode live berhenti)
  local TOT=0 _v; for _v in "$AV" "$AM" "$AT" "$AS"; do [[ "$_v" =~ ^[0-9]+$ ]] && TOT=$((TOT+_v)); done; [[ "$AV" =~ ^[0-9]+$ ]] || TOT="-"
  clear 2>/dev/null
  echo -e "${B}┌${IN}┐${N}"
  echo -e "${B}│${N}  ${W}CEK VPS (POTATO)${N}  ·  ${C}$(date '+%H:%M:%S')${N}"
  echo -e "${B}│${N}  ${C}$(hostname)${N}"
  echo -e "${B}├${IN}┤${N}"
  printf "${B}│${N}  ${G}%-8s${N}: $(clr $CPU)%3s%%${N} [$(clr $CPU)%s${N}] ${C}%s core${N}\n" "CPU" "$CPU" "$(bar $CPU)" "$CORE"
  printf "${B}│${N}  ${G}%-8s${N}: ${C}%s${N}\n" "Load" "$LAV"
  printf "${B}│${N}  ${G}%-8s${N}: $(clr $MP)%3s%%${N} [$(clr $MP)%s${N}] ${C}%s/%s MB${N}\n" "RAM" "$MP" "$(bar $MP)" "$MU" "$MT"
  printf "${B}│${N}  ${G}%-8s${N}: $(clr $SP)%3s%%${N} [$(clr $SP)%s${N}] ${C}%s/%s MB${N}\n" "Swap" "$SP" "$(bar $SP)" "$SU" "$ST"
  printf "${B}│${N}  ${G}%-8s${N}: $(clr $DP)%3s%%${N} [$(clr $DP)%s${N}] ${C}%s/%s${N}\n" "Disk /" "$DP" "$(bar $DP)" "$DU" "$DTT"
  echo -e "${B}├${IN}┤${N}"
  printf "${B}│${N}  ${G}%-8s${N}: ${Y}%s${N}\n" "Uptime" "$UPT"
  printf "${B}│${N}  ${G}%-8s${N}: ${C}▼ %s   ▲ %s${N}\n" "Trafik" "$DL" "$UL"
  printf "${B}│${N}  ${G}%-8s${N}: ${Y}%s${N} koneksi aktif\n" "Koneksi" "$CON"
  printf "${B}│${N}  ${G}%-8s${N}: ${Y}%s${N} ${B}(V:%s M:%s T:%s S:%s)${N}\n" "Akun" "$TOT" "$AV" "$AM" "$AT" "$AS"
  echo -e "${B}└${IN}┘${N}"
}
if [[ "$1" == live || "$1" == -l ]]; then trap 'echo; exit 0' INT; while true; do render; echo -e " ${Y}mode live · Ctrl-C untuk keluar${N}"; done
else render; fi
CEKVPS_EOF
chmod +x /usr/local/sbin/cekvps
bash -n /usr/local/sbin/cekvps && echo "SIAP: ketik  cekvps  atau  cekvps live"

# ---------- optimasicpu : RPS + antrian jaringan (DIJALANKAN MANUAL) ----------
cat > /usr/local/sbin/optimasicpu <<'SCRIPT'
#!/bin/bash
set -u
G='\e[32m'; Y='\e[33m'; C='\e[36m'; N='\e[0m'
CORES=$(nproc); MASK=$(printf '%x' $(( (1<<CORES) - 1 )))
IFACE=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}'); [ -z "$IFACE" ] && IFACE=$(ls /sys/class/net|grep -v lo|head -1)
echo -e "${C}== OPTIMASI CPU (jaringan) ==${N}"; echo -e " NIC:${Y}$IFACE${N} Core:${Y}$CORES${N} RPS mask:${Y}$MASK${N}"
sysctl -qw net.core.rps_sock_flow_entries=32768 2>/dev/null
n=0; for q in /sys/class/net/$IFACE/queues/rx-*; do [ -e "$q/rps_cpus" ] || continue; echo "$MASK">"$q/rps_cpus" 2>/dev/null && n=$((n+1)); echo 32768>"$q/rps_flow_cnt" 2>/dev/null; done
echo -e " RPS aktif di ${G}$n${N} queue."
sysctl -qw net.core.netdev_max_backlog=32768 net.core.netdev_budget=1200 net.core.netdev_budget_usecs=8000 net.core.somaxconn=8192 net.ipv4.tcp_max_syn_backlog=16384 2>/dev/null
echo " Antrian jaringan diperbesar."
if [ -e /proc/sys/net/netfilter/nf_conntrack_max ]; then cur=$(cat /proc/sys/net/netfilter/nf_conntrack_max); sysctl -qw net.netfilter.nf_conntrack_max=262144 2>/dev/null; [ -w /sys/module/nf_conntrack/parameters/hashsize ] && echo 65536>/sys/module/nf_conntrack/parameters/hashsize 2>/dev/null; echo " conntrack: $cur -> 262144 (kini $(cat /proc/sys/net/netfilter/nf_conntrack_count))"; else echo " conntrack: tidak aktif (dilewati)"; fi
if ls /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor >/dev/null 2>&1; then ok=0; for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance>"$g" 2>/dev/null && ok=$((ok+1)); done; echo " governor -> performance ($ok core)"; else echo " governor: virtual, dilewati"; fi
cat > /etc/sysctl.d/99-cas-cpu.conf <<SYS
net.core.rps_sock_flow_entries=32768
net.core.netdev_max_backlog=32768
net.core.netdev_budget=1200
net.core.netdev_budget_usecs=8000
net.core.somaxconn=8192
net.ipv4.tcp_max_syn_backlog=16384
SYS
[ -e /proc/sys/net/netfilter/nf_conntrack_max ] && echo "net.netfilter.nf_conntrack_max=262144" >> /etc/sysctl.d/99-cas-cpu.conf
cat > /usr/local/sbin/cas-nettune <<'BOOT'
#!/bin/bash
IFACE=$(ip route 2>/dev/null|awk '/^default/{print $5;exit}'); [ -z "$IFACE" ] && IFACE=$(ls /sys/class/net|grep -v lo|head -1)
CORES=$(nproc); MASK=$(printf '%x' $(( (1<<CORES)-1 )))
for q in /sys/class/net/$IFACE/queues/rx-*; do [ -e "$q/rps_cpus" ] && echo "$MASK">"$q/rps_cpus" 2>/dev/null; [ -e "$q/rps_flow_cnt" ] && echo 32768>"$q/rps_flow_cnt" 2>/dev/null; done
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -w "$g" ] && echo performance>"$g" 2>/dev/null; done
[ -w /sys/module/nf_conntrack/parameters/hashsize ] && echo 65536>/sys/module/nf_conntrack/parameters/hashsize 2>/dev/null
exit 0
BOOT
chmod +x /usr/local/sbin/cas-nettune
cat > /etc/systemd/system/cas-nettune.service <<UNIT
[Unit]
Description=Cassanova net/CPU tuning
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cas-nettune
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload 2>/dev/null; systemctl enable --now cas-nettune.service >/dev/null 2>&1
echo -e "${G} Tersimpan permanen (otomatis aktif lagi tiap reboot).${N}"
SCRIPT
chmod +x /usr/local/sbin/optimasicpu && echo "optimasicpu dibuat."

# ---------- optimasilog : loglevel Xray + logrotate (DIJALANKAN MANUAL) ----------
cat > /usr/local/sbin/optimasilog <<'SCRIPT'
#!/bin/bash
# optimasilog — turunkan loglevel Xray ke "warning" + pasang logrotate (KHUSUS Potato).
# Limit IP TIDAK terpengaruh (aus-cloud baca /proc/net, bukan log).
set -u
SYN=${SYN:-/etc/default/syncron}
LOGDIR=${LOGDIR:-/var/log/xray}
echo "== OPTIMASI LOG POTATO =="
[ -d "$SYN" ] || { echo "Folder config tidak ada: $SYN"; exit 1; }
changed=0
for f in "$SYN"/*/*.json; do
  [ -f "$f" ] || continue
  case "$f" in *.bak*) continue;; esac
  cur=$(grep -oE '"loglevel"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  [ -z "$cur" ] && { echo "  $f : (tak ada loglevel, dilewati)"; continue; }
  if [ "$cur" != "warning" ]; then
    cp -a "$f" "$f.bak-$(date +%F_%H%M%S)"
    sed -i -E 's/("loglevel"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"warning"/' "$f"
    echo "  $f : $cur -> warning"; changed=1
  else
    echo "  $f : sudah warning"
  fi
done
cat > /etc/logrotate.d/xray-access <<'ROT'
/var/log/xray/*.log {
    rotate 1
    size 20M
    copytruncate
    missingok
    notifempty
    compress
    su root root
}
ROT
cat > /etc/cron.hourly/xray-logrotate <<'CR'
#!/bin/bash
/usr/sbin/logrotate /etc/logrotate.d/xray-access
CR
chmod +x /etc/cron.hourly/xray-logrotate
/usr/sbin/logrotate -f /etc/logrotate.d/xray-access 2>/dev/null
echo "  logrotate terpasang + rotasi awal dijalankan."
if [ "$changed" = 1 ]; then
  echo
  echo "loglevel diubah. Agar aktif, service perlu di-restart (memutus koneksi ~beberapa detik)."
  read -rp "Restart drawit/paradis/sketsa SEKARANG? (y/t) : " yn
  if [ "$yn" = y ] || [ "$yn" = Y ]; then
    for s in drawit paradis sketsa; do
      systemctl restart "$s" 2>/dev/null && echo "  restart $s : OK" || echo "  restart $s : (tidak ada / gagal)"
    done
  else
    echo "  Dilewati. Jalankan nanti saat sepi:  systemctl restart drawit paradis sketsa"
  fi
else
  echo "  Tidak ada perubahan loglevel, restart tidak perlu."
fi
echo; echo "== HASIL =="
echo "-- loglevel sekarang --"
grep -rHoE '"loglevel"[[:space:]]*:[[:space:]]*"[^"]*"' "$SYN"/*/*.json 2>/dev/null | grep -v '\.bak'
echo "-- ukuran log --"; ls -lh "$LOGDIR"/ 2>/dev/null
SCRIPT
chmod +x /usr/local/sbin/optimasilog && echo "optimasilog dibuat."

# ---------- potatocmd : daftar perintah ----------
cat > /usr/local/sbin/potatocmd <<'PCEOF'
#!/bin/bash
G='\e[32m'; Y='\e[33m'; C='\e[36m'; D='\e[2m'; N='\e[0m'
LN="──────────────────────────────────────────"
r(){ printf "  ${C}%-20s${N} %s\n" "$1" "$2"; }
echo -e "$LN"; echo -e "  ${G}PERINTAH TAMBAHAN POTATO${N}"; echo -e "$LN"
echo -e " ${Y}CEK (hanya membaca, aman)${N}"
r "cek <nama/uuid>"    "cari akun: masa aktif, status, limit, kuota"
r "cekvps"             "ringkasan VPS + jumlah akun"
r "cekvps live"        "sama, diperbarui terus (Ctrl-C keluar)"
r "cekbeban"           "beban & kapasitas VPS + saran"
r "cekbeban live"      "sama, tiap 5 detik"
echo -e " ${Y}PERAWATAN (mengubah VPS, jalankan saat sepi)${N}"
r "bersihrecovery [n]" "hapus akun RECOVERY > n bulan (default 4)"
r "optimasicpu"        "bagi beban jaringan ke semua core"
r "optimasilog"        "kecilkan log Xray (bisa restart layanan)"
echo -e "$LN"
echo -e " ${D}Update: jalankan ulang baris pemasang potato-tools.sh${N}"
PCEOF
chmod +x /usr/local/sbin/potatocmd

# ---------- cek akhir ----------
echo
ok=1
for f in /usr/local/sbin/bersihrecovery /usr/local/sbin/cekbeban /usr/local/sbin/cekvps /usr/local/sbin/optimasicpu /usr/local/sbin/optimasilog /usr/local/sbin/potatocmd; do
  [[ -x "$f" ]] && bash -n "$f" 2>/dev/null || { echo -e "${R}Bermasalah: $f${N}"; ok=0; }
done
command -v python3 >/dev/null 2>&1 && { python3 -c "import ast; ast.parse(open('/usr/local/bin/cek').read())" 2>/dev/null || { echo -e "${R}Bermasalah: /usr/local/bin/cek${N}"; ok=0; }; }
(( ok )) && echo -e "${G}SELESAI. Semua perintah terpasang.${N}"
echo; /usr/local/sbin/potatocmd
