#!/bin/bash

# Renkler
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Versiyon
VERSION="6.1"

# Banner
show_banner() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 MULTI SOURCE RECON v$VERSION                  ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# İlerleme
show_progress() {
    echo -e "${CYAN}[$1/$2] $3${NC}"
}

# Başlangıç
show_banner

read -p "$(echo -e ${YELLOW}"Hedef domain (örn: hedef.com): "${NC})" domain

if [ -z "$domain" ]; then
    echo -e "${RED}[!] Domain girilmedi!${NC}"
    exit 1
fi

# Domain temizleme
domain=$(echo $domain | sed -E 's#https?://##' | sed 's/^www\.//' | cut -d'/' -f1)
echo -e "${BLUE}[*] Hedef: $domain${NC}\n"

# Dosya İsimleri
WAYBACK_URLS="wayback_urls.txt"
WAYBACK_SUBS="wayback_subs.txt"
SUBFINDER="subfinder.txt"
SUBLIST3R="sublist3r.txt"
CRTSH="crtsh.txt"
COMMONCRAWL="commoncrawl.txt"
ALIENVAULT="alienvault.txt"
RAPIDDNS="rapiddns.txt"
URLSCAN="urlscan.txt"
ALL_SUBS="all_subs.txt"
ACTIVE_SUBS="active_subs.txt"
FINAL="status_200.txt"
TEMP_DIR="temp_$$"
SUMMARY="ozet.txt"

# Temizlik ve Klasörleme
rm -f $WAYBACK_URLS $WAYBACK_SUBS $SUBFINDER $SUBLIST3R $CRTSH $COMMONCRAWL $ALIENVAULT $RAPIDDNS $URLSCAN $ALL_SUBS $ACTIVE_SUBS $FINAL $SUMMARY
mkdir -p $TEMP_DIR

total_steps=10
current_step=0

#---------------------------------------------------------------------
# 1. WAYBACK MACHINE
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Wayback Machine taranıyor..."
curl -s "http://web.archive.org/cdx/search/cdx?url=*.$domain/*&output=text&fl=original&collapse=urlkey" | sort -u > $WAYBACK_URLS
wayback_url_count=$(wc -l < $WAYBACK_URLS 2>/dev/null || echo "0")

if [ $wayback_url_count -gt 0 ]; then
    cat $WAYBACK_URLS | grep -oE "https?://[^/]*" | sed -E 's#https?://##' | sed 's/:.*//' | grep -E "\.$domain$" | sort -u > $WAYBACK_SUBS
    wayback_sub_count=$(wc -l < $WAYBACK_SUBS)
    echo -e "${GREEN}   ├─ $wayback_url_count URL bulundu.${NC}"
    echo -e "${GREEN}   └─ $wayback_sub_count benzersiz subdomain çıkarıldı.${NC}"
else
    touch $WAYBACK_SUBS
    echo -e "${YELLOW}   └─ Kayıt bulunamadı.${NC}"
fi

#---------------------------------------------------------------------
# 2. crt.sh
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "crt.sh (Sertifika Şeffaflığı) sorgulanıyor..."
curl -s "https://crt.sh/?q=%25.$domain&output=json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | sort -u > $CRTSH
crtsh_count=$(wc -l < $CRTSH 2>/dev/null || echo "0")
echo -e "${GREEN}   └─ $crtsh_count subdomain bulundu.${NC}"

#---------------------------------------------------------------------
# 3. CommonCrawl
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "CommonCrawl taranıyor..."
for year in {2022..2024}; do
    curl -s "http://index.commoncrawl.org/CC-MAIN-$year-*/index?url=*.$domain/*&output=json" 2>/dev/null | jq -r '.url?' 2>/dev/null >> $TEMP_DIR/commoncrawl_raw.txt
done

if [ -s $TEMP_DIR/commoncrawl_raw.txt ]; then
    cat $TEMP_DIR/commoncrawl_raw.txt | grep -oE "https?://[^/]*" | sed -E 's#https?://##' | sed 's/:.*//' | grep -E "\.$domain$" | sort -u > $COMMONCRAWL
    commoncrawl_count=$(wc -l < $COMMONCRAWL)
    echo -e "${GREEN}   └─ $commoncrawl_count subdomain bulundu.${NC}"
else
    touch $COMMONCRAWL
    echo -e "${YELLOW}   └─ Kayıt bulunamadı.${NC}"
fi

#---------------------------------------------------------------------
# 4. AlienVault OTX
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "AlienVault OTX sorgulanıyor..."
curl -s "https://otx.alienvault.com/api/v1/indicators/domain/$domain/passive_dns" | jq -r '.passive_dns[]?.hostname' 2>/dev/null | grep -E "\.$domain$" | sort -u > $ALIENVAULT
alienvault_count=$(wc -l < $ALIENVAULT 2>/dev/null || echo "0")
echo -e "${GREEN}   └─ $alienvault_count subdomain bulundu.${NC}"

#---------------------------------------------------------------------
# 5. RapidDNS
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "RapidDNS sorgulanıyor..."
curl -s "https://rapiddns.io/subdomain/$domain?full=1" | grep -oE "[a-zA-Z0-9.-]+\.$domain" | sort -u > $RAPIDDNS
rapiddns_count=$(wc -l < $RAPIDDNS 2>/dev/null || echo "0")
echo -e "${GREEN}   └─ $rapiddns_count subdomain bulundu.${NC}"

#---------------------------------------------------------------------
# 6. URLScan.io
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "URLScan.io sorgulanıyor..."
curl -s "https://urlscan.io/api/v1/search/?q=domain:$domain&size=10000" | jq -r '.results[]?.page?.domain' 2>/dev/null | grep -E "\.$domain$" | sort -u > $URLSCAN
urlscan_count=$(wc -l < $URLSCAN 2>/dev/null || echo "0")
echo -e "${GREEN}   └─ $urlscan_count subdomain bulundu.${NC}"

#---------------------------------------------------------------------
# 7. Subfinder
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Subfinder çalıştırılıyor..."
subfinder -d $domain -silent -all -recursive | sort -u > $SUBFINDER
subfinder_count=$(wc -l < $SUBFINDER 2>/dev/null || echo "0")
echo -e "${GREEN}   └─ $subfinder_count subdomain bulundu.${NC}"

#---------------------------------------------------------------------
# 8. BİRLEŞTİRME
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Tüm kaynaklar birleştiriliyor..."
cat $WAYBACK_SUBS $CRTSH $COMMONCRAWL $ALIENVAULT $RAPIDDNS $URLSCAN $SUBFINDER 2>/dev/null | \
    grep -v "^$" | \
    grep -E "^[a-zA-Z0-9.-]+\.$domain$" | \
    sort -u > $ALL_SUBS
total_count=$(wc -l < $ALL_SUBS)

if [ $total_count -eq 0 ]; then
    echo -e "${RED}[!] Hiç subdomain bulunamadı.${NC}"
    rm -rf $TEMP_DIR
    exit 1
fi
echo -e "${GREEN}   └─ Toplam $total_count benzersiz subdomain listelendi.${NC}"

#---------------------------------------------------------------------
# 9. AKTİFLİK KONTROLÜ (httpx)
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "HTTPX ile aktiflik kontrolü yapılıyor..."
if command -v httpx &> /dev/null; then
    httpx -l $ALL_SUBS -silent -threads 100 -o $ACTIVE_SUBS
    active_count=$(wc -l < $ACTIVE_SUBS 2>/dev/null || echo "0")
    
    # Status 200 Analizi
    httpx -l $ACTIVE_SUBS -mc 200 -sc -ip -title -server -tech-detect -silent -threads 100 -o $FINAL
    status_200_count=$(wc -l < $FINAL 2>/dev/null || echo "0")
    echo -e "${GREEN}   ├─ $active_count aktif subdomain tespit edildi.${NC}"
    echo -e "${GREEN}   └─ $status_200_count site '200 OK' döndürüyor.${NC}"
else
    echo -e "${YELLOW}   └─ httpx kurulu değil, aktiflik kontrolü atlanıyor.${NC}"
    active_count="N/A"
    status_200_count="N/A"
fi

#---------------------------------------------------------------------
# 10. ÖZET VE KAPANIŞ
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Rapor oluşturuluyor..."

{
    echo -e "MULTI SOURCE RECON ÖZET RAPORU"
    echo -e "=============================="
    echo -e "Hedef    : $domain"
    echo -e "Tarih    : $(date)"
    echo -e "------------------------------"
    echo -e "Kaynaklar:"
    echo -e "  Wayback     : $(wc -l < $WAYBACK_SUBS 2>/dev/null || echo 0)"
    echo -e "  crt.sh      : $crtsh_count"
    echo -e "  Subfinder   : $subfinder_count"
    echo -e "  AlienVault  : $alienvault_count"
    echo -e "------------------------------"
    echo -e "SONUÇLAR:"
    echo -e "  Toplam Benzersiz : $total_count"
    echo -e "  Toplam Aktif     : $active_count"
    echo -e "  Status 200 OK    : $status_200_count"
} > $SUMMARY

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}Dosyalar kaydedildi:${NC}"
echo -e " ├─ Tüm liste: $ALL_SUBS"
echo -e " ├─ Aktifler : $ACTIVE_SUBS"
echo -e " ├─ Detaylı  : $FINAL"
echo -e " └─ Özet     : $SUMMARY"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Temizlik
rm -rf $TEMP_DIR
echo -e "${GREEN}İşlem başarıyla tamamlandı.${NC}"
