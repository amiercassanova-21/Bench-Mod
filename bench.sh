#!/bin/bash
# =====================================================
#  BENCH-MOD  ·  mod by Cassanova Tunneling
#  base: bench.sh by Teddysun (https://github.com/teddysun/across)
#  Speedtest multi server operator seluler Indonesia + SG, memakai
#  Speedtest CLI resmi Ookla (versi dikunci + cek SHA-256).
#  Berdiri sendiri: bisa dipakai di VPS mana pun (tidak butuh SC).
#    bash <(curl -sSL .../bench.sh)              -> pilih mode
#    bash <(curl -sSL .../bench.sh) cepat|id|sg|lengkap|<id server>
# =====================================================
export LC_ALL=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
REPO_RAW=https://raw.githubusercontent.com/amiercassanova-21/Bench-Mod/main
WORK=${BENCH_DIR:-${HOME:-/root}/.bench-mod}
BIN=$WORK/speedtest
OOKLA_VER=1.2.0
declare -A OOKLA_SHA=( [x86_64]="5690596c54ff9bed63fa3732f818a05dbc2db19ad36ed68f21ca5f64d5cfeeb7" [aarch64]="3953d231da3783e2bf8904b6dd72767c5c6e533e163d3742fd0437affa431bd3" )
SRV_LOCAL=$WORK/servers.txt
mkdir -p "$WORK" 2>/dev/null
# masukan keyboard: dijalankan lewat "curl | bash" stdin berisi skrip, jadi baca dari /dev/tty
if [[ -t 0 ]]; then TTY=/dev/stdin; elif (: </dev/tty) 2>/dev/null; then TTY=/dev/tty; else TTY=""; fi
ask(){ local _a=""; [[ -n "$TTY" ]] && read -rp "$1" _a <"$TTY"; printf '%s' "$_a"; }

# ---------- warna (256 warna: aman di aplikasi terminal HP) ----------
E=$'\e'; N="${E}[0m"; B="${E}[1m"
c(){ printf '%s[38;5;%sm' "$E" "$1"; }
D=$(c 245); FR=$(c 61); W=$(c 255); G=$(c 114); Y=$(c 221); R=$(c 203); C=$(c 81); M=$(c 141)
GRAD=(93 99 105 111 117 123 159 123 117 111 105 99)
grad(){ local s="$1" i out=""; for ((i=0;i<${#s};i++)); do out+="$(c ${GRAD[i%${#GRAD[@]}]})${s:i:1}"; done; printf '%s%s%s' "$B" "$out" "$N"; }
HL="──────────────────────────────────────────"
top(){ printf '%s╭%s╮%s\n' "$FR" "$HL" "$N"; }
bot(){ printf '%s╰%s╯%s\n' "$FR" "$HL" "$N"; }
bl(){ printf '%s│%s %b\n' "$FR" "$N" "$1"; }
BLN=(Jan Feb Mar Apr Mei Jun Jul Agu Sep Okt Nov Des)
tgl(){ printf '%s %s %s' "$(date +%d)" "${BLN[$((10#$(date +%m)-1))]}" "$(date '+%Y %H:%M %Z')"; }
opname(){ case "$1" in TELKOMSEL) echo Tsel;; INDOSAT) echo Indosat;; XL) echo XL;; *) echo "";; esac; }
opcol(){ case "$1" in TELKOMSEL) echo 196;; INDOSAT) echo 220;; XL) echo 33;; *) echo 245;; esac; }

# ---------- daftar server: operator|kota|ID/SG|id ----------
# Daftar terbaru diambil dari repo (bisa diganti tanpa rilis versi baru);
# kalau gagal, pakai salinan terakhir / bawaan di bawah ini.
DEFAULT_SERVERS='TELKOMSEL|Jakarta|ID|71028
TELKOMSEL|Surabaya|ID|70730
TELKOMSEL|Medan|ID|70718
TELKOMSEL|Batam|ID|43255
TELKOMSEL|Telin SG|SG|37744
INDOSAT|Jakarta|ID|13039
INDOSAT|Surabaya|ID|36700
INDOSAT|Medan|ID|39334
INDOSAT|Batam|ID|18108
INDOSAT|SG|SG|13058
XL|Jakarta|ID|68900
XL|Surabaya|ID|61853
XL|Medan|ID|67458
XL|SG|SG|42688'
load_servers(){
  local t
  if [[ "${BENCH_NO_FETCH:-0}" != 1 ]]; then
    t=$(mktemp)
    if curl -fsS --max-time 8 "$REPO_RAW/speedtest-servers.txt" -o "$t" 2>/dev/null && grep -qE '^[A-Z]+\|[^|]+\|(ID|SG)\|[0-9]+$' "$t"; then
      grep -E '^[A-Z]+\|[^|]+\|(ID|SG)\|[0-9]+$' "$t" > "$SRV_LOCAL"
    fi
    rm -f "$t"
  fi
  if [[ -s "$SRV_LOCAL" ]]; then cat "$SRV_LOCAL"; else printf '%s\n' "$DEFAULT_SERVERS"; fi
}

# ---------- pasang Speedtest CLI resmi Ookla (versi dikunci + SHA-256) ----------
ensure_cli(){
  [[ -x "$BIN" ]] && return 0
  local a sha url t
  a=$(uname -m); [[ "$a" == arm64 ]] && a=aarch64
  sha=${OOKLA_SHA[$a]}
  [[ -n "$sha" && "$sha" != __* ]] || { echo -e " ${R}Arsitektur $a belum didukung speedtest.${N}"; return 1; }
  url="https://install.speedtest.net/app/cli/ookla-speedtest-$OOKLA_VER-linux-$a.tgz"
  echo -e " ${D}Memasang Speedtest CLI $OOKLA_VER (sekali saja)...${N}"
  t=$(mktemp -d)
  if curl -fsSL --max-time 60 "$url" -o "$t/s.tgz" && [[ "$(sha256sum "$t/s.tgz" | cut -d' ' -f1)" == "$sha" ]] \
     && tar -xzf "$t/s.tgz" -C "$t" speedtest; then
    install -m 755 "$t/speedtest" "$BIN"
  else
    echo -e " ${R}Gagal mengunduh/memverifikasi Speedtest CLI. Coba lagi nanti.${N}"
  fi
  rm -rf "$t"; [[ -x "$BIN" ]]
}

# ---------- satu tes -> "dl ul ping jitter loss url" (Mbps, ms) atau kosong ----------
run_one(){ # $1 = id server (kosong = terdekat)
  local j args=(--accept-license --accept-gdpr -f json)
  [[ -n "$1" ]] && args+=(-s "$1")
  local dl ul pg jt ls url
  j=$(timeout 120 "$BIN" "${args[@]}" </dev/null 2>/dev/null | grep '"type":"result"') || return 1
  # dibaca tanpa jq supaya bisa jalan di VPS mana pun
  dl=$(grep -oP '"download":\{[^}]*"bandwidth":\K[0-9]+' <<<"$j"); ul=$(grep -oP '"upload":\{[^}]*"bandwidth":\K[0-9]+' <<<"$j")
  pg=$(grep -oP '"ping":\{[^}]*"latency":\K[0-9]+' <<<"$j"); jt=$(grep -oP '"ping":\{[^}]*"jitter":\K[0-9]+' <<<"$j")
  ls=$(grep -oP '"packetLoss":\K[0-9]+' <<<"$j"); url=$(grep -oP '"result":\{[^}]*"url":"\K[^"]+' <<<"$j")
  [[ -n "$dl" && -n "$ul" ]] || return 1
  echo "$(( dl*8/1000000 )) $(( ul*8/1000000 )) ${pg:-0} ${jt:-0} ${ls:-0} ${url:--}"
}

# ---------- tampilan ----------
mb(){ (( $1 >= 10000 )) && awk -v v="$1" 'BEGIN{printf "%.1fG", v/1000}' || printf '%s' "$1"; }
# bar mengikuti UP (arah VPS ke pelanggan), skala tetap: 100/250/500/1000/1500/2000 Mbps
sbar(){ local n=0 t i out="" cols=(172 178 184 148 112 76)
  for t in 100 250 500 1000 1500 2000; do (( $1 >= t )) && n=$((n+1)); done; ((n<1))&&n=1
  for ((i=0;i<6;i++)); do if ((i<n)); then out+="$(c ${cols[i]})▰"; else out+="$(c 238)▱"; fi; done; printf '%s%s' "$out" "$N"; }
pcol(){ (( $1 < 30 )) && printf '%s' "$G" || { (( $1 < 80 )) && printf '%s' "$Y" || printf '%s' "$R"; }; }
row(){ # $1 kota  $2 down  $3 up  $4 ping  $5 loss%
  local lo=""; (( ${5:-0} > 0 )) && lo=" ${R}${5}%${N}"
  printf ' %s%-10s%s %s %s%5s%s %s%5s%s %s%4sms%s%s\n' "$W" "$1" "$N" "$(sbar $3)" "$C" "$(mb $2)" "$N" "$M" "$(mb $3)" "$N" "$(pcol $4)" "$4" "$N" "$lo"; }
failrow(){ printf ' %s%-10s%s %s! server tidak aktif · dilewati%s\n' "$W" "$1" "$N" "$Y" "$N"; }
waitrow(){ printf ' %s%-10s · menunggu%s\n' "$D" "$1" "$N"; }

header(){
  clear 2>/dev/null; echo
  printf ' %s\n' "$(grad '▌ C A S S A N O V A  S P E E D T E S T ▐')"
  printf ' %smod by%s %sCassanova Tunneling%s\n' "$D" "$N" "$M$B" "$N"
  printf ' %sbase   bench.sh by Teddysun%s\n' "$D" "$N"
}
# info lokasi VPS (sekali per jalan): ipwho.is, cadangan ip-api.com
get_ipinfo(){
  local j
  j=$(curl -fsS --max-time 6 https://ipwho.is/ 2>/dev/null)
  if [[ "$j" == *'"success":true'* ]]; then
    V_CITY=$(grep -oP '"city":"\K[^"]*' <<<"$j"); V_CC=$(grep -oP '"country_code":"\K[^"]*' <<<"$j")
    V_ISP=$(grep -oP '"connection":\{[^}]*"isp":"\K[^"]*' <<<"$j")
  else
    j=$(curl -fsS --max-time 6 "http://ip-api.com/json/?fields=city,countryCode,isp" 2>/dev/null)
    V_CITY=$(grep -oP '"city":"\K[^"]*' <<<"$j"); V_CC=$(grep -oP '"countryCode":"\K[^"]*' <<<"$j")
    V_ISP=$(grep -oP '"isp":"\K[^"]*' <<<"$j")
  fi
  V_CITY=${V_CITY:--}; V_CC=${V_CC:-ID}; V_ISP=${V_ISP:--}
}
vps_box(){
  local isp core ram disk os
  isp=$V_ISP; (( ${#isp} > 22 )) && isp="${isp:0:21}…"
  core=$(nproc 2>/dev/null); ram=$(free -m | awk '/Mem:/{printf "%.1f", $2/1024}')
  disk=$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$2); print $2}')
  os=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}" | sed 's/ GNU\/Linux//; s/ LTS//'); (( ${#os} > 30 )) && os="${os:0:29}…"
  top
  bl "${C}VPS ${N} ${V_CITY} · ${isp} ${D}(${V_CC})${N}"
  bl "${C}SPEK${N} ${core} core · RAM ${ram} GB · Disk ${disk} GB"
  bl "${C}OS  ${N} ${os} · $(uname -m)"
  bl "${C}MODE${N} ${Y}${MODE_LBL}${N} · ${#SEL[@]} server · ±$(( (${#SEL[@]}*25+59)/60 )) menit"
  bot
}
render(){ # $1 = baris progres (kosong = selesai)
  local i op prev="" r
  header; vps_box
  printf ' %s%-10s %-6s %5s %5s %6s%s\n' "$D" "SERVER" "" "DOWN" "UP" "PING" "$N"
  printf ' %s%-10s %-6s %5s %5s %6s%s\n' "$D" "" "" "Mbps" "Mbps" "" "$N"
  printf ' %sUP = arah VPS ke pelanggan · %% = loss%s\n' "$D" "$N"
  for ((i=0;i<${#SEL[@]};i++)); do
    IFS='|' read -r op city _ _ <<<"${SEL[i]}"
    if [[ "$op" != "$prev" ]]; then
      local cnt=0; for r in "${SEL[@]}"; do [[ "${r%%|*}" == "$op" ]] && cnt=$((cnt+1)); done
      local nm=$op; [[ $op == XL ]] && nm="XL AXIATA"; [[ $op == NEAR ]] && nm="TERDEKAT"
      printf '\n %s●%s %s%s%s %s· %s server%s\n' "$(c $(opcol $op))" "$N" "$B$W" "$nm" "$N" "$D" "$cnt" "$N"; prev=$op
    fi
    if [[ -z "${RES[i]}" ]]; then waitrow "$city"
    elif [[ "${RES[i]}" == FAIL ]]; then failrow "$city"
    else read -r dl ul pg _ ls _ <<<"${RES[i]}"; row "$city" "$dl" "$ul" "$pg" "$ls"; fi
  done
  [[ -n "$1" ]] && printf '\n %s%s%s\n' "$Y" "$1" "$N"
}

mbg(){ (( $1 >= 1000 )) && awk -v v="$1" 'BEGIN{printf "%.2f Gbps", v/1000}' || printf '%s Mbps' "$1"; }
summary(){
  local i op city cc dl ul pg n=0 maxdl=0 near=0 sum=0 pn=0 fails=() lines=() weak=() tg=()
  local -A bu bp bc su sn
  for ((i=0;i<${#SEL[@]};i++)); do
    IFS='|' read -r op city cc _ <<<"${SEL[i]}"
    if [[ "${RES[i]}" == FAIL || -z "${RES[i]}" ]]; then local o; o=$(opname "$op"); fails+=("${o:+$o }$city"); continue; fi
    read -r dl ul pg _ <<<"${RES[i]}"
    n=$((n+1)); (( dl > maxdl )) && maxdl=$dl
    [[ "$cc" == ID && "$op" != NEAR ]] && { sum=$((sum+pg)); pn=$((pn+1)); }
    [[ "$op" == NEAR ]] && continue
    su[$op]=$(( ${su[$op]:-0} + ul )); sn[$op]=$(( ${sn[$op]:-0} + 1 ))
    # terbaik per operator: UP terbesar (selisih <10% dianggap sama), lalu ping terendah
    if [[ -z "${bc[$op]}" ]] || (( ul*10 > ${bu[$op]}*11 )) || (( ul*11 >= ${bu[$op]}*10 && pg < ${bp[$op]} )); then
      bu[$op]=$ul; bp[$op]=$pg; bc[$op]=$city
    fi
  done
  # batas VPS: hampir semua download mentok di angka yang sama
  for ((i=0;i<${#SEL[@]};i++)); do read -r dl _ <<<"${RES[i]}"; [[ "$dl" =~ ^[0-9]+$ ]] && (( dl*10 >= maxdl*9 )) && near=$((near+1)); done
  echo; top
  bl "${B}${W}RINGKASAN${N}"
  if (( n >= 3 && near*10 >= n*7 )); then bl "▲ Batas VPS : ${C}±$(mbg $maxdl)${N} ${D}(semua mentok)${N}"; tg+=("Batas VPS ±$(mbg $maxdl)"); fi
  (( pn )) && { bl "◉ Ping ID   : $(pcol $((sum/pn)))$((sum/pn)) ms${N} rata-rata"; tg+=("Ping ID $((sum/pn)) ms"); }
  local maxa=0 a
  for op in TELKOMSEL INDOSAT XL; do [[ -n "${bc[$op]}" ]] || continue; a=$(( su[$op]/sn[$op] )); (( a > maxa )) && maxa=$a; done
  for op in TELKOMSEL INDOSAT XL; do
    [[ -n "${bc[$op]}" ]] || continue
    lines+=("$(printf '  %s%-8s%s %-9s %s↑%5s%s · %s%2s ms%s' "$(c $(opcol $op))" "$(opname $op)" "$N" "${bc[$op]}" "$M" "$(mb ${bu[$op]})" "$N" "$(pcol ${bp[$op]})" "${bp[$op]}" "$N")")
    tg+=("$(opname $op) ${bc[$op]} ↑$(mb ${bu[$op]}) ${bp[$op]}ms")
    a=$(( su[$op]/sn[$op] )); (( a*10 < maxa*6 )) && weak+=("$(opname $op) ke pelanggan ±$(( (a+5)/10*10 )) Mbps")
  done
  if (( ${#lines[@]} )); then
    bl "★ Terbaik per operator ${D}(arah ke pelanggan)${N}"
    for i in "${lines[@]}"; do bl "$i"; done
  fi
  # mode satu server (tanpa operator): tampilkan hasilnya saja
  if (( ! ${#lines[@]} && n )); then
    for ((i=0;i<${#SEL[@]};i++)); do [[ "${RES[i]}" == FAIL || -z "${RES[i]}" ]] && continue
      read -r dl ul pg _ <<<"${RES[i]}"; bl "★ Hasil : ${C}↓$(mb $dl)${N} ${M}↑$(mb $ul)${N} · $(pcol $pg)${pg} ms${N}"; tg+=("↓$(mb $dl) ↑$(mb $ul) ${pg}ms"); done
  fi
  for i in "${weak[@]}"; do bl "${Y}! ${i}${N}"; tg+=("! $i"); done
  (( ${#fails[@]} )) && { bl "${Y}! Gagal ${#fails[@]} server${N} ($(IFS=,; echo "${fails[*]}" | sed 's/,/, /g' | cut -c1-24))"; tg+=("Gagal: ${#fails[@]} server"); }
  bot
  SUM_TXT=$(printf '%s\n' "${tg[@]}")
}

choose_mode(){
  header; echo
  echo -e " ${C}1.)${N} Cepat      ${D}terdekat + 3 operator · ±2 mnt${N}"
  echo -e " ${C}2.)${N} Indonesia  ${D}semua kota operator ID${N}"
  echo -e " ${C}3.)${N} Singapura  ${D}server SG tiap operator${N}"
  echo -e " ${C}4.)${N} Lengkap    ${D}semua kota · ±5-6 mnt${N}"
  echo -e " ${C}5.)${N} Pilih ID   ${D}satu server Speedtest${N}"
  echo -e " ${C}x.)${N} Keluar\n"
  [[ -z "$TTY" ]] && { MODE=cepat; return; }     # tanpa keyboard -> mode cepat
  o=$(ask "$(echo -e " ${G}Pilih : ${N}")")
  case "$o" in 1) MODE=cepat;; 2) MODE=id;; 3) MODE=sg;; 4) MODE=lengkap;;
    5) MODE=$(ask " ID server : "); [[ "$MODE" =~ ^[0-9]+$ ]] || exit 0;; *) exit 0;; esac
}

# ---------- utama ----------
main(){
MODE=${1:-}
[[ -z "$MODE" ]] && choose_mode
command -v curl >/dev/null || { echo "curl belum terpasang"; exit 1; }
ensure_cli || exit 1
get_ipinfo; VPSCC=$V_CC
mapfile -t ALL < <(load_servers)
SEL=()
case "$MODE" in
  cepat)   MODE_LBL=Cepat; SEL+=("NEAR|Terdekat|$VPSCC|")
           # VPS di SG: server SG tiap operator; selain itu: Jakarta tiap operator
           for op in TELKOMSEL INDOSAT XL; do
             for s in "${ALL[@]}"; do IFS='|' read -r o city cc _ <<<"$s"; [[ $o != "$op" ]] && continue
               if [[ "$VPSCC" == SG ]]; then [[ $cc == SG ]] && { SEL+=("$s"); break; }
               else [[ $city == Jakarta ]] && { SEL+=("$s"); break; }; fi
             done
           done ;;
  id)      MODE_LBL=Indonesia; for s in "${ALL[@]}"; do [[ "$s" == *"|ID|"* ]] && SEL+=("$s"); done ;;
  sg)      MODE_LBL=Singapura; for s in "${ALL[@]}"; do [[ "$s" == *"|SG|"* ]] && SEL+=("$s"); done ;;
  lengkap) MODE_LBL=Lengkap
           # urutan per operator: region VPS lebih dulu.
           # VPS di Indonesia: kota ID saja (rute ke SG tidak dipakai pelanggannya; tetap ada di mode sg)
           for op in TELKOMSEL INDOSAT XL; do
             for pass in first second; do for s in "${ALL[@]}"; do IFS='|' read -r o _ cc _ <<<"$s"; [[ $o != "$op" ]] && continue
               if [[ $pass == first ]]; then [[ $cc == "$VPSCC" ]] && SEL+=("$s"); elif [[ $VPSCC != ID ]]; then [[ $cc != "$VPSCC" ]] && SEL+=("$s"); fi
             done; done
           done ;;
  [0-9]*)  MODE_LBL="Server $MODE"; SEL+=("NEAR|ID $MODE|ID|$MODE") ;;
  *) echo "Pakai: bench.sh [cepat|id|sg|lengkap|<id server>]"; exit 1 ;;
esac
(( ${#SEL[@]} )) || { echo "Tidak ada server untuk mode ini."; exit 1; }

if [[ -n "$TTY" && "${BENCH_YES:-0}" != 1 ]]; then
  header; vps_box
  echo -e "\n ${Y}Selama tes, bandwidth VPS terpakai penuh sehingga koneksi${N}"
  echo -e " ${Y}pengguna lain bisa melambat sebentar.${N}"
  go=$(ask "$(echo -e " ${G}Enter = mulai · x = batal : ${N}")"); [[ "$go" == x || "$go" == X ]] && exit 0
fi

declare -a RES=(); START=$(date +%s)
SPIN=(◐ ◓ ◑ ◒)
for ((i=0;i<${#SEL[@]};i++)); do
  IFS='|' read -r op city cc id <<<"${SEL[i]}"
  _o=$(opname "$op"); render "${SPIN[i%4]} [$((i+1))/${#SEL[@]}] ${_o:+$_o }${city} · mengukur..."
  if out=$(run_one "$id"); then
    read -r dl ul pg jt ls url _ <<<"$out"
    RES[i]="$dl $ul $pg $jt $ls $url"
  else RES[i]=FAIL; fi
done
render ""
summary
EL=$(( $(date +%s) - START ))
printf ' %s◷ %dm %02ds · %s%s\n' "$D" $((EL/60)) $((EL%60)) "$(tgl)" "$N"
echo
}
while :; do
  main "$@"
  [[ -n "$TTY" && "${BENCH_YES:-0}" != 1 ]] || exit 0
  a=$(ask "$(printf ' %s[u]%s Ulangi  %s[x]%s Keluar : ' "$C" "$N" "$C" "$N")")
  [[ "$a" == u || "$a" == U ]] || exit 0
  set -- "$MODE"
done
