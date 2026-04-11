#!/bin/bash

# Renk kodları
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Versiyon
VERSION="2.0"

# Kontrol fonksiyonu
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}[!] $1 bulunamadı. Lütfen yükleyin.${NC}"
        echo -e "${YELLOW}Kurulum komutu: $2${NC}"
        return 1
    fi
    return 0
}

# Banner göster
show_banner() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              PROFESYONEL SUBDOMAİN KEŞİF ARACI                 ║${NC}"
    echo -e "${BLUE}║                     Multi-Source Recon v$VERSION                    ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# İlerleme göster
show_progress() {
    echo -e "${CYAN}[$1/$2] $3${NC}"
}

#---------------------------------------------------------------------
# TOOL KONTROLLERİ
#---------------------------------------------------------------------
show_banner

echo -e "${YELLOW}[*] Gerekli araçlar kontrol ediliyor...${NC}"

# Temel araçlar (her sistemde olmalı)
check_tool "curl" "sudo apt install curl -y"
check_tool "jq" "sudo apt install jq -y"
check_tool "grep" "sudo apt install grep -y"
check_tool "sort" "sudo apt install coreutils -y"

# Ek araçlar (opsiyonel)
SUBFINDER_INSTALLED=false
SUBLIST3R_INSTALLED=false
HTTPX_INSTALLED=false

if check_tool "subfinder" "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"; then
    SUBFINDER_INSTALLED=true
    echo -e "${GREEN}  ✓ subfinder hazır${NC}"
fi

if check_tool "sublist3r" "pip install sublist3r"; then
    SUBLIST3R_INSTALLED=true
    echo -e "${GREEN}  ✓ sublist3r hazır${NC}"
fi

if check_tool "httpx" "go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"; then
    HTTPX_INSTALLED=true
    echo -e "${GREEN}  ✓ httpx hazır${NC}"
fi

echo ""

# Kullanıcıdan domain al
read -p "$(echo -e ${YELLOW}"Hedef domaini girin: "${NC})" domain

if [ -z "$domain" ]; then
    echo -e "${RED}[!] Domain girilmedi.${NC}"
    exit 1
fi

# Domain'i temizle
domain=$(echo $domain | sed -E 's#https?://##' | sed 's/^www\.//' | cut -d'/' -f1)

echo -e "${BLUE}[*] Hedef domain: $domain${NC}"
echo ""

# Çıktı dosyaları
WAYBACK_URLS="wayback_urls.txt"
WAYBACK_SUBDOMAINS="wayback_subdomains.txt"
SUBFINDER_FILE="subfinder_subdomains.txt"
SUBLIST3R_FILE="sublist3r_subdomains.txt"
CRTSH_FILE="crtsh_subdomains.txt"
COMMONCRAWL_FILE="commoncrawl_subdomains.txt"
VIRUSTOTAL_FILE="virustotal_subdomains.txt"
RAPIDDNS_FILE="rapiddns_subdomains.txt"
ALIENVAULT_FILE="alienvault_subdomains.txt"
URLSCAN_FILE="urlscan_subdomains.txt"
SUBDOMAINS_FILE="all_subdomains.txt"
ACTIVE_SUBDOMAINS_FILE="active_subdomains.txt"
FINAL_OUTPUT="results_200.txt"
TEMP_DIR="temp_$$"
SUMMARY_FILE="summary.txt"

# Temizlik ve hazırlık
rm -f $WAYBACK_URLS $WAYBACK_SUBDOMAINS $SUBFINDER_FILE $SUBLIST3R_FILE $CRTSH_FILE
rm -f $COMMONCRAWL_FILE $VIRUSTOTAL_FILE $RAPIDDNS_FILE $ALIENVAULT_FILE
rm -f $URLSCAN_FILE $SUBDOMAINS_FILE $ACTIVE_SUBDOMAINS_FILE $FINAL_OUTPUT $SUMMARY_FILE
mkdir -p $TEMP_DIR

total_steps=11
current_step=0

#---------------------------------------------------------------------
# 1. WAYBACK MACHINE (SİZİN İSTEDİĞİNİZ FORMATTA)
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Wayback Machine taranıyor..."

echo -e "${CYAN}   ├─ curl -s \"http://web.archive.org/cdx/search/cdx?url=*.$domain/*&output=text&fl=original&collapse=urlkey\"${NC}"
curl -s "http://web.archive.org/cdx/search/cdx?url=*.$domain/*&output=text&fl=original&collapse=urlkey" | sort -u > $WAYBACK_URLS

wayback_url_count=$(wc -l < $WAYBACK_URLS 2>/dev/null || echo "0")
echo -e "${GREEN}   ├─ $wayback_url_count URL bulundu.${NC}"

# URL'lerden subdomainleri çıkar
if [ $wayback_url_count -gt 0 ]; then
    cat $WAYBACK_URLS | grep -oE "https?://[^/]*" | sed -E 's#https?://##' | sed 's/:.*//' | grep -E "\.$domain$" | sort -u > $WAYBACK_SUBDOMAINS
    wayback_subdomain_count=$(wc -l < $WAYBACK_SUBDOMAINS)
    echo -e "${GREEN}   └─ $wayback_subdomain_count benzersiz subdomain çıkarıldı.${NC}"

    # Örnek göster
    if [ $wayback_subdomain_count -gt 0 ]; then
        echo -e "${CYAN}      Örnek subdomainler:${NC}"
        head -5 $WAYBACK_SUBDOMAINS | sed 's/^/         → /'
    fi
else
    touch $WAYBACK_SUBDOMAINS
    wayback_subdomain_count=0
    echo -e "${YELLOW}   └─ Wayback Machine'den veri alınamadı.${NC}"
fi

#---------------------------------------------------------------------
# 2. crt.sh (Certificate Transparency)
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "crt.sh taranıyor..."

echo -e "${CYAN}   ├─ curl -s https://crt.sh/?q=%25.$domain&output=json${NC}"
curl -s "https://crt.sh/?q=%25.$domain&output=json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | sort -u > $CRTSH_FILE

crtsh_count=$(wc -l < $CRTSH_FILE 2>/dev/null || echo "0")
if [ $crtsh_count -gt 0 ]; then
    echo -e "${GREEN}   └─ $crtsh_count subdomain bulundu.${NC}"
else
    echo -e "${YELLOW}   └─ crt.sh'den sonuç alınamadı.${NC}"
    touch $CRTSH_FILE
fi

#---------------------------------------------------------------------
# 3. CommonCrawl
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "CommonCrawl taranıyor..."

echo -e "${CYAN}   ├─ CommonCrawl indeksleri taranıyor...${NC}"
for year in {2020..2024}; do
    curl -s "http://index.commoncrawl.org/CC-MAIN-$year-*/index?url=*.$domain/*&output=json" 2>/dev/null | jq -r '.url' 2>/dev/null >> $TEMP_DIR/commoncrawl_raw.txt
done

if [ -s $TEMP_DIR/commoncrawl_raw.txt ]; then
    cat $TEMP_DIR/commoncrawl_raw.txt | grep -oE "https?://[^/]*" | sed -E 's#https?://##' | sed 's/:.*//' | grep -E "\.$domain$" | sort -u > $COMMONCRAWL_FILE
    commoncrawl_count=$(wc -l < $COMMONCRAWL_FILE)
    echo -e "${GREEN}   └─ $commoncrawl_count subdomain bulundu.${NC}"
else
    echo -e "${YELLOW}   └─ CommonCrawl'dan sonuç alınamadı.${NC}"
    touch $COMMONCRAWL_FILE
fi

#---------------------------------------------------------------------
# 4. AlienVault OTX
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "AlienVault OTX taranıyor..."

echo -e "${CYAN}   ├─ curl -s https://otx.alienvault.com/api/v1/indicators/domain/$domain/passive_dns${NC}"
curl -s "https://otx.alienvault.com/api/v1/indicators/domain/$domain/passive_dns" | jq -r '.passive_dns[]?.hostname' 2>/dev/null | grep -E "\.$domain$" | sort -u > $ALIENVAULT_FILE

alienvault_count=$(wc -l < $ALIENVAULT_FILE 2>/dev/null || echo "0")
if [ $alienvault_count -gt 0 ]; then
    echo -e "${GREEN}   └─ $alienvault_count subdomain bulundu.${NC}"
else
    echo -e "${YELLOW}   └─ AlienVault'dan sonuç alınamadı.${NC}"
    touch $ALIENVAULT_FILE
fi

#---------------------------------------------------------------------
# 5. RapidDNS
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "RapidDNS taranıyor..."

echo -e "${CYAN}   ├─ curl -s https://rapiddns.io/subdomain/$domain?full=1${NC}"
curl -s "https://rapiddns.io/subdomain/$domain?full=1" | grep -oE "[a-zA-Z0-9.-]+\.$domain" | sort -u > $RAPIDDNS_FILE

rapiddns_count=$(wc -l < $RAPIDDNS_FILE 2>/dev/null || echo "0")
if [ $rapiddns_count -gt 0 ]; then
    echo -e "${GREEN}   └─ $rapiddns_count subdomain bulundu.${NC}"
else
    echo -e "${YELLOW}   └─ RapidDNS'den sonuç alınamadı.${NC}"
    touch $RAPIDDNS_FILE
fi

#---------------------------------------------------------------------
# 6. URLScan
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "URLScan.io taranıyor..."

echo -e "${CYAN}   ├─ curl -s https://urlscan.io/api/v1/search/?q=domain:$domain${NC}"
curl -s "https://urlscan.io/api/v1/search/?q=domain:$domain&size=10000" | jq -r '.results[]?.page?.domain' 2>/dev/null | grep -E "\.$domain$" | sort -u > $URLSCAN_FILE

urlscan_count=$(wc -l < $URLSCAN_FILE 2>/dev/null || echo "0")
if [ $urlscan_count -gt 0 ]; then
    echo -e "${GREEN}   └─ $urlscan_count subdomain bulundu.${NC}"
else
    echo -e "${YELLOW}   └─ URLScan'den sonuç alınamadı.${NC}"
    touch $URLSCAN_FILE
fi

#---------------------------------------------------------------------
# 7. SUBFINDER (eğer yüklüyse)
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Subfinder ile subdomain taranıyor..."

if [ "$SUBFINDER_INSTALLED" = true ]; then
    echo -e "${CYAN}   ├─ subfinder -d $domain -silent -all -recursive${NC}"
    subfinder -d $domain -silent -all -recursive -timeout 10 -max-time 30 | sort -u > $SUBFINDER_FILE

    subfinder_count=$(wc -l < $SUBFINDER_FILE)
    echo -e "${GREEN}   └─ $subfinder_count subdomain bulundu.${NC}"
else
    echo -e "${YELLOW}   └─ Subfinder yüklü değil, atlanıyor.${NC}"
    touch $SUBFINDER_FILE
    subfinder_count=0
fi

#---------------------------------------------------------------------
# 8. SUBLIST3R (eğer yüklüyse)
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Sublist3r ile subdomain taranıyor..."

if [ "$SUBLIST3R_INSTALLED" = true ]; then
    echo -e "${CYAN}   ├─ sublist3r -d $domain -o temp.txt${NC}"
    sublist3r -d $domain -o $TEMP_DIR/sublist3r_output.txt > /dev/null 2>&1

    if [ -f $TEMP_DIR/sublist3r_output.txt ]; then
        cat $TEMP_DIR/sublist3r_output.txt | sort -u > $SUBLIST3R_FILE
        sublist3r_count=$(wc -l < $SUBLIST3R_FILE)
        echo -e "${GREEN}   └─ $sublist3r_count subdomain bulundu.${NC}"
    else
        echo -e "${YELLOW}   └─ Sublist3r sonuç vermedi.${NC}"
        touch $SUBLIST3R_FILE
        sublist3r_count=0
    fi
else
    echo -e "${YELLOW}   └─ Sublist3r yüklü değil, atlanıyor.${NC}"
    touch $SUBLIST3R_FILE
    sublist3r_count=0
fi

#---------------------------------------------------------------------
# 9. TÜM SUBDOMAİNLERİ BİRLEŞTİR
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Subdomain'ler birleştiriliyor..."

# Tüm kaynakları birleştir
cat $WAYBACK_SUBDOMAINS $CRTSH_FILE $COMMONCRAWL_FILE $ALIENVAULT_FILE $RAPIDDNS_FILE $URLSCAN_FILE $SUBFINDER_FILE $SUBLIST3R_FILE 2>/dev/null | \
    grep -v "^$" | \
    grep -E "^[a-zA-Z0-9.-]+\.$domain$" | \
    grep -v "^\." | \
    grep -v "\.$" | \
    sed 's/^www\.//' | \
    sort -u > $SUBDOMAINS_FILE

total_count=$(wc -l < $SUBDOMAINS_FILE)
echo -e "${GREEN}   └─ Toplam $total_count benzersiz subdomain bulundu.${NC}"

if [ $total_count -eq 0 ]; then
    echo -e "${RED}[!] Hiç subdomain bulunamadı. Program sonlandırılıyor.${NC}"
    rm -rf $TEMP_DIR
    exit 1
fi

# Subdomainleri dosyaya kaydet ve göster
echo -e "${CYAN}   ├─ İlk 10 subdomain:${NC}"
head -10 $SUBDOMAINS_FILE | sed 's/^/      → /'

#---------------------------------------------------------------------
# 10. AKTİF SUBDOMAİNLERİ BUL
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Aktif subdomain'ler taranıyor (httpx)..."

if [ "$HTTPX_INSTALLED" = true ]; then
    echo -e "${CYAN}   ├─ httpx ile $total_count subdomain taranıyor...${NC}"
    httpx -l $SUBDOMAINS_FILE -silent -threads 100 -timeout 7 -retries 2 -o $ACTIVE_SUBDOMAINS_FILE

    active_count=$(wc -l < $ACTIVE_SUBDOMAINS_FILE)
    echo -e "${GREEN}   └─ $active_count aktif subdomain bulundu.${NC}"

    if [ $active_count -gt 0 ]; then
        echo -e "${CYAN}      Aktif subdomain örnekleri:${NC}"
        head -5 $ACTIVE_SUBDOMAINS_FILE | sed 's/^/         → /'
    fi
else
    echo -e "${YELLOW}   └─ Httpx yüklü değil, aktif subdomain tespiti atlanıyor.${NC}"
    cp $SUBDOMAINS_FILE $ACTIVE_SUBDOMAINS_FILE
    active_count=$total_count
fi

#---------------------------------------------------------------------
# 11. STATUS 200 OLANLARI VE TEKNOLOJİLERİ GÖSTER
#---------------------------------------------------------------------
((current_step++))
show_progress $current_step $total_steps "Status 200 ve teknoloji tespiti yapılıyor..."

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        STATUS CODE 200 OLAN SUBDOMAİNLER VE TEKNOLOJİLERİ       ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

status_200_count=0

if [ -s $ACTIVE_SUBDOMAINS_FILE ] && [ "$HTTPX_INSTALLED" = true ]; then
    # httpx ile status code 200 olanları ve teknolojileri tespit et
    httpx -l $ACTIVE_SUBDOMAINS_FILE -status-code -tech-detect -silent -threads 50 -timeout 7 -retries 1 > $TEMP_DIR/httpx_results.txt

    # Status 200 olanları filtrele
    grep "\[200\]" $TEMP_DIR/httpx_results.txt > $TEMP_DIR/status_200.txt

    if [ -s $TEMP_DIR/status_200.txt ]; then
        status_200_count=$(wc -l < $TEMP_DIR/status_200.txt)
        counter=1

        while read line; do
            # URL'i ve teknolojileri ayır
            url=$(echo "$line" | awk '{print $1}')
            tech=$(echo "$line" | grep -o "\[[^]]*\]" | tail -1 | sed 's/[][]//g')

            echo -e "${GREEN}[$counter] $url${NC}"
            if [ ! -z "$tech" ] && [ "$tech" != "200" ]; then
                echo -e "    ${YELLOW}Teknolojiler:${NC} $tech"
            else
                echo -e "    ${RED}Teknoloji tespit edilemedi${NC}"
            fi
            echo ""

            # Sonuçları dosyaya kaydet
            echo "$url - Teknolojiler: $tech" >> $FINAL_OUTPUT
            ((counter++))
        done < $TEMP_DIR/status_200.txt
    else
        echo -e "${RED}[!] Status code 200 dönen subdomain bulunamadı.${NC}"
    fi
else
    echo -e "${RED}[!] Aktif subdomain bulunamadı veya httpx yüklü değil.${NC}"
fi

#---------------------------------------------------------------------
# ÖZET RAPOR
#---------------------------------------------------------------------
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                         ÖZET RAPOR                            ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Her kaynaktan gelen subdomain sayılarını hesapla
final_wayback=$(cat $WAYBACK_SUBDOMAINS 2>/dev/null | wc -l)
final_crtsh=$(cat $CRTSH_FILE 2>/dev/null | wc -l)
final_commoncrawl=$(cat $COMMONCRAWL_FILE 2>/dev/null | wc -l)
final_alienvault=$(cat $ALIENVAULT_FILE 2>/dev/null | wc -l)
final_rapiddns=$(cat $RAPIDDNS_FILE 2>/dev/null | wc -l)
final_urlscan=$(cat $URLSCAN_FILE 2>/dev/null | wc -l)
final_subfinder=$subfinder_count
final_sublist3r=$sublist3r_count

# Renkli özet tablosu
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "Wayback Machine" "$final_wayback"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "crt.sh" "$final_crtsh"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "CommonCrawl" "$final_commoncrawl"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "AlienVault OTX" "$final_alienvault"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "RapidDNS" "$final_rapiddns"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "URLScan.io" "$final_urlscan"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "Subfinder" "$final_subfinder"
printf "${GREEN}%-20s ${NC}: ${YELLOW}%8d${NC} subdomain\n" "Sublist3r" "$final_sublist3r"
echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
printf "${BLUE}%-20s ${NC}: ${GREEN}%8d${NC} subdomain\n" "TOPLAM BENZERSİZ" "$total_count"
printf "${BLUE}%-20s ${NC}: ${GREEN}%8d${NC} subdomain\n" "AKTİF SUBDOMAİN" "$active_count"
printf "${BLUE}%-20s ${NC}: ${GREEN}%8d${NC} subdomain\n" "STATUS 200 OK" "$status_200_count"

# Zaman damgası
echo ""
echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}Tarama tamamlanma zamanı: $(date)${NC}"
echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"

#---------------------------------------------------------------------
# DOSYA KAYIT VE TEMİZLİK
#---------------------------------------------------------------------
echo ""
echo -e "${MAGENTA}Dosyalar:${NC}"
echo -e "  ├─ Tüm subdomainler     : ${GREEN}$SUBDOMAINS_FILE${NC} ($total_count kayıt)"
echo -e "  ├─ Aktif subdomainler   : ${GREEN}$ACTIVE_SUBDOMAINS_FILE${NC} ($active_count kayıt)"
echo -e "  ├─ Status 200 sonuçları : ${GREEN}$FINAL_OUTPUT${NC} ($status_200_count kayıt)"
echo -e "  ├─ Wayback URL'leri     : ${GREEN}$WAYBACK_URLS${NC} ($wayback_url_count kayıt)"
echo -e "  └─ Wayback subdomainler : ${GREEN}$WAYBACK_SUBDOMAINS${NC} ($final_wayback kayıt)"

# Özet dosyası oluştur
cat > $SUMMARY_FILE << EOF
╔═══════════════════════════════════════════════════════════════╗
║                    TARAMA ÖZET RAPORU                        ║
╚═══════════════════════════════════════════════════════════════╝

Hedef Domain    : $domain
Tarama Zamanı   : $(date)

KAYNAK BAZLI SONUÇLAR:
────────────────────────────────────
Wayback Machine   : $final_wayback subdomain
crt.sh            : $final_crtsh subdomain
CommonCrawl       : $final_commoncrawl subdomain
AlienVault OTX    : $final_alienvault subdomain
RapidDNS          : $final_rapiddns subdomain
URLScan.io        : $final_urlscan subdomain
Subfinder         : $final_subfinder subdomain
Sublist3r         : $final_sublist3r subdomain

TOPLAM SONUÇLAR:
────────────────────────────────────
Benzersiz Subdomain : $total_count
Aktif Subdomain     : $active_count
Status 200 OK       : $status_200_count

DOSYALAR:
────────────────────────────────────
Tüm subdomainler     : $SUBDOMAINS_FILE
Aktif subdomainler   : $ACTIVE_SUBDOMAINS_FILE
Status 200 sonuçları : $FINAL_OUTPUT
Wayback URL'leri     : $WAYBACK_URLS
Wayback subdomainler : $WAYBACK_SUBDOMAINS

╔═══════════════════════════════════════════════════════════════╗
║                    TARAMA TAMAMLANDI                         ║
╚═══════════════════════════════════════════════════════════════╝
EOF

echo -e "  └─ Özet rapor           : ${GREEN}$SUMMARY_FILE${NC}"

# Geçici dosyaları temizle
rm -rf $TEMP_DIR

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    TARAMA BAŞARIYLA TAMAMLANDI                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"