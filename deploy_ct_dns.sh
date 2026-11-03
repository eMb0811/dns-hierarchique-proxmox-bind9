#!/bin/bash
# ==============================================================================
# TP ADMINISTRATION RÉSEAU — INFRASTRUCTURE DNS HIÉRARCHIQUE (1 CT PAR NOEUD)
# Serveur Proxmox : 10.153.4.186 (Bridge interne : vmbr1 - 192.168.100.0/24)
#
# Architecture complète (18 Conteneurs LXC actifs + 1 Template de base CT 200) :
#   - Racine (1 CT) :
#       * CT 201 (dns-root)            : 192.168.100.10 — Zone "."
#   - 4 ccTLD (4 CTs) :
#       * CT 211 (dns-cctld-ma)        : 192.168.100.11 — Zone "ma"
#       * CT 212 (dns-cctld-ml)        : 192.168.100.12 — Zone "ml"
#       * CT 213 (dns-cctld-ci)        : 192.168.100.13 — Zone "ci"
#       * CT 214 (dns-cctld-gn)        : 192.168.100.14 — Zone "gn"
#   - Niveau 1 : 4 Domaines (4 CTs) :
#       * CT 221 (dns-mbarry-ma)       : 192.168.100.21 — Zone "mbarry.ma"
#       * CT 222 (dns-odiop-ml)        : 192.168.100.22 — Zone "odiop.ml"
#       * CT 223 (dns-mniass-ci)       : 192.168.100.23 — Zone "mniass.ci"
#       * CT 224 (dns-mthiongane-gn)   : 192.168.100.24 — Zone "mthiongane.gn"
#   - Niveau 2 : 8 Feuilles — 2 par noeud de Niveau 1 (8 CTs) :
#       * CT 231 (dns-it-mbarry-ma)    : 192.168.100.31 — Zone "it.mbarry.ma"
#       * CT 232 (dns-rh-mbarry-ma)    : 192.168.100.32 — Zone "rh.mbarry.ma"
#       * CT 233 (dns-it-odiop-ml)     : 192.168.100.33 — Zone "it.odiop.ml"
#       * CT 234 (dns-rh-odiop-ml)     : 192.168.100.34 — Zone "rh.odiop.ml"
#       * CT 235 (dns-it-mniass-ci)    : 192.168.100.35 — Zone "it.mniass.ci"
#       * CT 236 (dns-rh-mniass-ci)    : 192.168.100.36 — Zone "rh.mniass.ci"
#       * CT 237 (dns-it-mthiongane-gn): 192.168.100.37 — Zone "it.mthiongane.gn"
#       * CT 238 (dns-rh-mthiongane-gn): 192.168.100.38 — Zone "rh.mthiongane.gn"
#   - Client / Résolveur Récursif (1 CT) :
#       * CT 250 (dns-client)          : 192.168.100.50 — Résolveur récursif
# ==============================================================================

set -euo pipefail

STORAGE="local-lvm"
BRIDGE="vmbr1"
GW="192.168.100.1"
SUBNET_MASK="24"
UPSTREAM_DNS="172.16.2.11"
CT_PASS="passer2026"
BASE_TEMPLATE_ID=200

# --- IPs par noeud de l'arbre DNS ---
IP_ROOT="192.168.100.10"

IP_MA="192.168.100.11"
IP_ML="192.168.100.12"
IP_CI="192.168.100.13"
IP_GN="192.168.100.14"

IP_MBARRY="192.168.100.21"
IP_ODIOP="192.168.100.22"
IP_MNIASS="192.168.100.23"
IP_MTHIONGANE="192.168.100.24"

IP_IT_MBARRY="192.168.100.31"
IP_RH_MBARRY="192.168.100.32"
IP_IT_ODIOP="192.168.100.33"
IP_RH_ODIOP="192.168.100.34"
IP_IT_MNIASS="192.168.100.35"
IP_RH_MNIASS="192.168.100.36"
IP_IT_MTHIONGANE="192.168.100.37"
IP_RH_MTHIONGANE="192.168.100.38"

IP_CLIENT="192.168.100.50"

# --- Liste des 18 Conteneurs LXC à déployer ---
ALL_CTS=(
    "201:dns-root:${IP_ROOT}"
    "211:dns-cctld-ma:${IP_MA}"
    "212:dns-cctld-ml:${IP_ML}"
    "213:dns-cctld-ci:${IP_CI}"
    "214:dns-cctld-gn:${IP_GN}"
    "221:dns-mbarry-ma:${IP_MBARRY}"
    "222:dns-odiop-ml:${IP_ODIOP}"
    "223:dns-mniass-ci:${IP_MNIASS}"
    "224:dns-mthiongane-gn:${IP_MTHIONGANE}"
    "231:dns-it-mbarry-ma:${IP_IT_MBARRY}"
    "232:dns-rh-mbarry-ma:${IP_RH_MBARRY}"
    "233:dns-it-odiop-ml:${IP_IT_ODIOP}"
    "234:dns-rh-odiop-ml:${IP_RH_ODIOP}"
    "235:dns-it-mniass-ci:${IP_IT_MNIASS}"
    "236:dns-rh-mniass-ci:${IP_RH_MNIASS}"
    "237:dns-it-mthiongane-gn:${IP_IT_MTHIONGANE}"
    "238:dns-rh-mthiongane-gn:${IP_RH_MTHIONGANE}"
    "250:dns-client:${IP_CLIENT}"
)

echo "=============================================================================="
echo " 1. PRÉPARATION DU RÉSEAU HÔTE PROXMOX (NAT vmbr1 -> vmbr0)"
echo "=============================================================================="
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if ! iptables -t nat -C POSTROUTING -s 192.168.100.0/24 -o vmbr0 -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o vmbr0 -j MASQUERADE
fi
echo "[OK] IP Forwarding et NAT MASQUERADE actifs pour 192.168.100.0/24."

echo ""
echo "=============================================================================="
echo " 2. NETTOYAGE DES ANCIENS CONTENEURS (201..250)"
echo "=============================================================================="
for id in 201 202 203 204 205 211 212 213 214 221 222 223 224 231 232 233 234 235 236 237 238 250; do
    if pct status "$id" &>/dev/null; then
        echo "[CLEAN] Suppression de l'ancien CT $id..."
        pct stop "$id" &>/dev/null || true
        pct destroy "$id" --purge 1 &>/dev/null || true
    fi
done

echo ""
echo "=============================================================================="
echo " 3. VÉRIFICATION / CRÉATION DU TEMPLATE DE BASE LXC (CT 200 : dns-base)"
echo "=============================================================================="
if ! pct config "$BASE_TEMPLATE_ID" &>/dev/null; then
    echo "[BASE] Création du CT de base $BASE_TEMPLATE_ID (dns-base) avec bind9 et dnsutils..."
    VZTMPL="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    pct create "$BASE_TEMPLATE_ID" "$VZTMPL" \
        --hostname "dns-base" \
        --password "$CT_PASS" \
        --storage "$STORAGE" \
        --rootfs "${STORAGE}:4" \
        --cores 1 \
        --memory 256 \
        --swap 256 \
        --net0 "name=eth0,bridge=${BRIDGE},ip=192.168.100.200/${SUBNET_MASK},gw=${GW}" \
        --nameserver "$UPSTREAM_DNS" \
        --unprivileged 1 \
        --features nesting=1
    pct start "$BASE_TEMPLATE_ID"
    sleep 4
    pct exec "$BASE_TEMPLATE_ID" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        echo 'nameserver ${UPSTREAM_DNS}' > /etc/resolv.conf
        apt-get update -qq
        apt-get install -y -qq bind9 bind9utils dnsutils >/dev/null
        mkdir -p /etc/bind/zones
        chown -R bind:bind /etc/bind/zones
    "
    pct stop "$BASE_TEMPLATE_ID"
    pct template "$BASE_TEMPLATE_ID"
    echo "[OK] Template CT $BASE_TEMPLATE_ID (dns-base) créé et converti en template."
else
    echo "[OK] Template CT $BASE_TEMPLATE_ID (dns-base) déjà présent."
fi

echo ""
echo "=============================================================================="
echo " 4. CLONAGE ET DÉMARRAGE DES 18 CONTENEURS LXC (1 CT PAR NOEUD DNS)"
echo "=============================================================================="
for entry in "${ALL_CTS[@]}"; do
    IFS=':' read -r CTID CTNAME CTIP <<< "$entry"
    echo "[CLONE] Clonage de CT $CTID ($CTNAME) -> IP: ${CTIP}/${SUBNET_MASK}..."
    while pct config "$BASE_TEMPLATE_ID" 2>/dev/null | grep -q "^lock:"; do
        sleep 1
    done
    pct clone "$BASE_TEMPLATE_ID" "$CTID" --hostname "$CTNAME" --full 0 >/dev/null
    pct set "$CTID" \
        --net0 "name=eth0,bridge=${BRIDGE},ip=${CTIP}/${SUBNET_MASK},gw=${GW}" \
        --nameserver "$UPSTREAM_DNS" \
        --memory 256 \
        --swap 256 \
        --onboot 1
    pct start "$CTID"
done

echo "[WAIT] Attente du démarrage des 18 conteneurs (4s)..."
sleep 4

# S'assurer que /etc/bind/zones existe et que bind9 est installé sur chaque clone
for entry in "${ALL_CTS[@]}"; do
    IFS=':' read -r CTID CTNAME CTIP <<< "$entry"
    pct exec "$CTID" -- bash -c "
        if ! command -v named >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            echo 'nameserver ${UPSTREAM_DNS}' > /etc/resolv.conf
            apt-get update -qq && apt-get install -y -qq bind9 bind9utils dnsutils >/dev/null
        fi
        mkdir -p /etc/bind/zones
        chown -R bind:bind /etc/bind/zones
    "
done

# Fonction utilitaire pour injecter named.conf.options et /usr/share/dns/root.hints sur les noeuds
configure_authoritative_options() {
    local ctid="$1"
    pct exec "$ctid" -- tee /etc/bind/named.conf.options >/dev/null << 'EOF'
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-recursion { any; };
    allow-query { any; };
    dnssec-validation no;
    listen-on { any; };
    listen-on-v6 { any; };
    minimal-responses no;
};
EOF
    if [ "$ctid" != "201" ]; then
        pct exec "$ctid" -- tee /usr/share/dns/root.hints >/dev/null << 'EOF'
;       Fichier /usr/share/dns/root.hints (TP Administration Reseau)
;       Serveurs racines publics d Internet commentes selon la consigne du professeur :
; .                        3600000      NS    A.ROOT-SERVERS.NET.
; A.ROOT-SERVERS.NET.      3600000      A     198.41.0.4
;
; --- Serveur Racine de notre Groupe (Groupe D : 192.168.100.10) ---
.                        3600000      NS    D.ROOT-SERVERS.NET.
D.ROOT-SERVERS.NET.      3600000      A     192.168.100.10
EOF
    fi
    pct exec "$ctid" -- bash -c "echo 'nameserver 127.0.0.1' > /etc/resolv.conf"
}

# ==============================================================================
# 5. CONFIGURATION DU SERVEUR RACINE : CT 201 (dns-root - 192.168.100.10)
#    Zone 1/17 : "." (db.root — D.ROOT-SERVERS.NET.)
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 5. CONFIGURATION DU SERVEUR RACINE (CT 201 : dns-root - ${IP_ROOT})"
echo "=============================================================================="
configure_authoritative_options 201

# Désactiver la zone "." hint dans named.conf.default-zones
pct exec 201 -- sed -i '/zone "\." {/,/};/ s/^/\/\/ /' /etc/bind/named.conf.default-zones

pct exec 201 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "." {
    type master;
    file "/etc/bind/zones/db.root";
};
EOF

pct exec 201 -- tee /etc/bind/zones/db.root >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA D.ROOT-SERVERS.NET. admin.ROOT-SERVERS.NET. (
            2026102903  ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Negative Cache TTL

; Serveur d'autorité de la Racine "." (Groupe D : 192.168.100.10) + Glue Record
@                       IN  NS      D.ROOT-SERVERS.NET.
D.ROOT-SERVERS.NET.     IN  A       192.168.100.10
A.ROOT-SERVERS.NET.     IN  A       10.153.4.224
ns1.root-servers.net.   IN  A       192.168.100.10

; Délégation des 4 ccTLD vers leurs 4 CTs dédiés + Glue Records
ma.                     IN  NS      ns1.ma.
ns1.ma.                 IN  A       192.168.100.11

ml.                     IN  NS      ns1.ml.
ns1.ml.                 IN  A       192.168.100.12

ci.                     IN  NS      ns1.ci.
ns1.ci.                 IN  A       192.168.100.13

gn.                     IN  NS      ns1.gn.
ns1.gn.                 IN  A       192.168.100.14

; Interconnexion Inter-Racines avec l'autre groupe (Racine 10.153.4.224 — CT 110)
ba.                     IN  NS      ns1.nic.ba.
ns1.nic.ba.             IN  A       10.153.4.225

diallo.                 IN  NS      ns1.nic.diallo.
ns1.nic.diallo.         IN  A       10.153.4.226

cisse.                  IN  NS      ns1.nic.cisse.
ns1.nic.cisse.          IN  A       10.153.4.247

diasse.                 IN  NS      ns1.nic.diasse.
ns1.nic.diasse.         IN  A       10.153.4.246

; Interconnexion avec l'autre serveur Proxmox physique (.sn, .org, .com : 10.153.4.229, .230, .231)
sn.                     IN  NS      ns.sn.
ns.sn.                  IN  A       10.153.4.229

org.                    IN  NS      ns.org.
ns.org.                 IN  A       10.153.4.230

com.                    IN  NS      ns.com.
ns.com.                 IN  A       10.153.4.231
EOF

pct exec 201 -- bash -c "
    chown -R bind:bind /etc/bind/zones
    named-checkconf
    named-checkzone . /etc/bind/zones/db.root
    systemctl restart named
    systemctl enable named >/dev/null 2>&1
"

# ==============================================================================
# 6. CONFIGURATION DES 4 CTs ccTLD (CT 211..214 : .ma, .ml, .ci, .gn)
#    Zones 2/17 à 5/17
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 6. CONFIGURATION DES 4 CTs ccTLD (CT 211..214 : .ma, .ml, .ci, .gn)"
echo "=============================================================================="

# --- CT 211 : Zone "ma" (192.168.100.11) ---
configure_authoritative_options 211
pct exec 211 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "ma" {
    type master;
    file "/etc/bind/zones/db.ma";
};
EOF
pct exec 211 -- tee /etc/bind/zones/db.ma >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.ma. admin.ma. (
            2026102701 3600 1800 604800 86400 )

@               IN  NS      ns1.ma.
ns1.ma.         IN  A       192.168.100.11

; Délégation de mbarry.ma vers CT 221 (192.168.100.21) + Glue Record
mbarry.ma.      IN  NS      ns1.mbarry.ma.
ns1.mbarry.ma.  IN  A       192.168.100.21
EOF
pct exec 211 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone ma /etc/bind/zones/db.ma && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 212 : Zone "ml" (192.168.100.12) ---
configure_authoritative_options 212
pct exec 212 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "ml" {
    type master;
    file "/etc/bind/zones/db.ml";
};
EOF
pct exec 212 -- tee /etc/bind/zones/db.ml >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.ml. admin.ml. (
            2026102701 3600 1800 604800 86400 )

@               IN  NS      ns1.ml.
ns1.ml.         IN  A       192.168.100.12

; Délégation de odiop.ml vers CT 222 (192.168.100.22) + Glue Record
odiop.ml.       IN  NS      ns1.odiop.ml.
ns1.odiop.ml.   IN  A       192.168.100.22
EOF
pct exec 212 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone ml /etc/bind/zones/db.ml && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 213 : Zone "ci" (192.168.100.13) ---
configure_authoritative_options 213
pct exec 213 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "ci" {
    type master;
    file "/etc/bind/zones/db.ci";
};
EOF
pct exec 213 -- tee /etc/bind/zones/db.ci >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.ci. admin.ci. (
            2026102701 3600 1800 604800 86400 )

@               IN  NS      ns1.ci.
ns1.ci.         IN  A       192.168.100.13

; Délégation de mniass.ci vers CT 223 (192.168.100.23) + Glue Record
mniass.ci.      IN  NS      ns1.mniass.ci.
ns1.mniass.ci.  IN  A       192.168.100.23
EOF
pct exec 213 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone ci /etc/bind/zones/db.ci && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 214 : Zone "gn" (192.168.100.14) ---
configure_authoritative_options 214
pct exec 214 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "gn" {
    type master;
    file "/etc/bind/zones/db.gn";
};
EOF
pct exec 214 -- tee /etc/bind/zones/db.gn >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.gn. admin.gn. (
            2026102701 3600 1800 604800 86400 )

@                   IN  NS      ns1.gn.
ns1.gn.             IN  A       192.168.100.14

; Délégation de mthiongane.gn vers CT 224 (192.168.100.24) + Glue Record
mthiongane.gn.      IN  NS      ns1.mthiongane.gn.
ns1.mthiongane.gn.  IN  A       192.168.100.24
EOF
pct exec 214 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone gn /etc/bind/zones/db.gn && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# ==============================================================================
# 7. CONFIGURATION DES 4 CTs NIVEAU 1 (CT 221..224 : 4 DN)
#    Zones 6/17 à 9/17 : mbarry.ma, odiop.ml, mniass.ci, mthiongane.gn
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 7. CONFIGURATION DES 4 CTs NIVEAU 1 (CT 221..224 : 4 DN)"
echo "=============================================================================="

# --- CT 221 : Zone "mbarry.ma" (192.168.100.21) ---
configure_authoritative_options 221
pct exec 221 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "mbarry.ma" {
    type master;
    file "/etc/bind/zones/db.mbarry.ma";
};
EOF
pct exec 221 -- tee /etc/bind/zones/db.mbarry.ma >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.mbarry.ma. admin.mbarry.ma. (
            2026102701 3600 1800 604800 86400 )

@                   IN  NS      ns1.mbarry.ma.
@                   IN  MX 10   mail.mbarry.ma.
@                   IN  A       192.168.100.21
ns1                 IN  A       192.168.100.21
www                 IN  A       192.168.100.21
mail                IN  A       192.168.100.21
portail             IN  CNAME   www.mbarry.ma.

; Délégation des 2 feuilles (it.mbarry.ma -> CT 231, rh.mbarry.ma -> CT 232) + Glue Records
it.mbarry.ma.       IN  NS      ns1.it.mbarry.ma.
ns1.it.mbarry.ma.   IN  A       192.168.100.31

rh.mbarry.ma.       IN  NS      ns1.rh.mbarry.ma.
ns1.rh.mbarry.ma.   IN  A       192.168.100.32
EOF
pct exec 221 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone mbarry.ma /etc/bind/zones/db.mbarry.ma && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 222 : Zone "odiop.ml" (192.168.100.22) ---
configure_authoritative_options 222
pct exec 222 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "odiop.ml" {
    type master;
    file "/etc/bind/zones/db.odiop.ml";
};
EOF
pct exec 222 -- tee /etc/bind/zones/db.odiop.ml >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.odiop.ml. admin.odiop.ml. (
            2026102701 3600 1800 604800 86400 )

@                   IN  NS      ns1.odiop.ml.
@                   IN  MX 10   mail.odiop.ml.
@                   IN  A       192.168.100.22
ns1                 IN  A       192.168.100.22
www                 IN  A       192.168.100.22
mail                IN  A       192.168.100.22
portail             IN  CNAME   www.odiop.ml.

; Délégation des 2 feuilles (it.odiop.ml -> CT 233, rh.odiop.ml -> CT 234) + Glue Records
it.odiop.ml.        IN  NS      ns1.it.odiop.ml.
ns1.it.odiop.ml.    IN  A       192.168.100.33

rh.odiop.ml.        IN  NS      ns1.rh.odiop.ml.
ns1.rh.odiop.ml.    IN  A       192.168.100.34
EOF
pct exec 222 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone odiop.ml /etc/bind/zones/db.odiop.ml && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 223 : Zone "mniass.ci" (192.168.100.23) ---
configure_authoritative_options 223
pct exec 223 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "mniass.ci" {
    type master;
    file "/etc/bind/zones/db.mniass.ci";
};
EOF
pct exec 223 -- tee /etc/bind/zones/db.mniass.ci >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.mniass.ci. admin.mniass.ci. (
            2026102701 3600 1800 604800 86400 )

@                   IN  NS      ns1.mniass.ci.
@                   IN  MX 10   mail.mniass.ci.
@                   IN  A       192.168.100.23
ns1                 IN  A       192.168.100.23
www                 IN  A       192.168.100.23
mail                IN  A       192.168.100.23
portail             IN  CNAME   www.mniass.ci.

; Délégation des 2 feuilles (it.mniass.ci -> CT 235, rh.mniass.ci -> CT 236) + Glue Records
it.mniass.ci.       IN  NS      ns1.it.mniass.ci.
ns1.it.mniass.ci.   IN  A       192.168.100.35

rh.mniass.ci.       IN  NS      ns1.rh.mniass.ci.
ns1.rh.mniass.ci.   IN  A       192.168.100.36
EOF
pct exec 223 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone mniass.ci /etc/bind/zones/db.mniass.ci && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 224 : Zone "mthiongane.gn" (192.168.100.24) ---
configure_authoritative_options 224
pct exec 224 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "mthiongane.gn" {
    type master;
    file "/etc/bind/zones/db.mthiongane.gn";
};
EOF
pct exec 224 -- tee /etc/bind/zones/db.mthiongane.gn >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.mthiongane.gn. admin.mthiongane.gn. (
            2026102701 3600 1800 604800 86400 )

@                       IN  NS      ns1.mthiongane.gn.
@                       IN  MX 10   mail.mthiongane.gn.
@                       IN  A       192.168.100.24
ns1                     IN  A       192.168.100.24
www                     IN  A       192.168.100.24
mail                    IN  A       192.168.100.24
portail                 IN  CNAME   www.mthiongane.gn.

; Délégation des 2 feuilles (it.mthiongane.gn -> CT 237, rh.mthiongane.gn -> CT 238) + Glue Records
it.mthiongane.gn.       IN  NS      ns1.it.mthiongane.gn.
ns1.it.mthiongane.gn.   IN  A       192.168.100.37

rh.mthiongane.gn.       IN  NS      ns1.rh.mthiongane.gn.
ns1.rh.mthiongane.gn.   IN  A       192.168.100.38
EOF
pct exec 224 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone mthiongane.gn /etc/bind/zones/db.mthiongane.gn && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# ==============================================================================
# 8. CONFIGURATION DES 8 CTs NIVEAU 2 (CT 231..238 : 8 FEUILLES it.* et rh.*)
#    Zones 10/17 à 17/17
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 8. CONFIGURATION DES 8 CTs NIVEAU 2 (CT 231..238 : 8 FEUILLES)"
echo "=============================================================================="

# --- CT 231 : Zone "it.mbarry.ma" (192.168.100.31) ---
configure_authoritative_options 231
pct exec 231 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "it.mbarry.ma" {
    type master;
    file "/etc/bind/zones/db.it.mbarry.ma";
};
EOF
pct exec 231 -- tee /etc/bind/zones/db.it.mbarry.ma >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.it.mbarry.ma. admin.it.mbarry.ma. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.it.mbarry.ma.
@       IN  MX 10   mail.it.mbarry.ma.
@       IN  A       192.168.100.31
ns1     IN  A       192.168.100.31
www     IN  A       192.168.100.31
mail    IN  A       192.168.100.31
portail IN  CNAME   www.it.mbarry.ma.
EOF
pct exec 231 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone it.mbarry.ma /etc/bind/zones/db.it.mbarry.ma && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 232 : Zone "rh.mbarry.ma" (192.168.100.32) ---
configure_authoritative_options 232
pct exec 232 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "rh.mbarry.ma" {
    type master;
    file "/etc/bind/zones/db.rh.mbarry.ma";
};
EOF
pct exec 232 -- tee /etc/bind/zones/db.rh.mbarry.ma >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.rh.mbarry.ma. admin.rh.mbarry.ma. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.rh.mbarry.ma.
@       IN  MX 10   mail.rh.mbarry.ma.
@       IN  A       192.168.100.32
ns1     IN  A       192.168.100.32
www     IN  A       192.168.100.32
mail    IN  A       192.168.100.32
portail IN  CNAME   www.rh.mbarry.ma.
EOF
pct exec 232 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone rh.mbarry.ma /etc/bind/zones/db.rh.mbarry.ma && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 233 : Zone "it.odiop.ml" (192.168.100.33) ---
configure_authoritative_options 233
pct exec 233 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "it.odiop.ml" {
    type master;
    file "/etc/bind/zones/db.it.odiop.ml";
};
EOF
pct exec 233 -- tee /etc/bind/zones/db.it.odiop.ml >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.it.odiop.ml. admin.it.odiop.ml. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.it.odiop.ml.
@       IN  MX 10   mail.it.odiop.ml.
@       IN  A       192.168.100.33
ns1     IN  A       192.168.100.33
www     IN  A       192.168.100.33
mail    IN  A       192.168.100.33
portail IN  CNAME   www.it.odiop.ml.
EOF
pct exec 233 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone it.odiop.ml /etc/bind/zones/db.it.odiop.ml && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 234 : Zone "rh.odiop.ml" (192.168.100.34) ---
configure_authoritative_options 234
pct exec 234 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "rh.odiop.ml" {
    type master;
    file "/etc/bind/zones/db.rh.odiop.ml";
};
EOF
pct exec 234 -- tee /etc/bind/zones/db.rh.odiop.ml >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.rh.odiop.ml. admin.rh.odiop.ml. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.rh.odiop.ml.
@       IN  MX 10   mail.rh.odiop.ml.
@       IN  A       192.168.100.34
ns1     IN  A       192.168.100.34
www     IN  A       192.168.100.34
mail    IN  A       192.168.100.34
portail IN  CNAME   www.rh.odiop.ml.
EOF
pct exec 234 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone rh.odiop.ml /etc/bind/zones/db.rh.odiop.ml && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 235 : Zone "it.mniass.ci" (192.168.100.35) ---
configure_authoritative_options 235
pct exec 235 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "it.mniass.ci" {
    type master;
    file "/etc/bind/zones/db.it.mniass.ci";
};
EOF
pct exec 235 -- tee /etc/bind/zones/db.it.mniass.ci >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.it.mniass.ci. admin.it.mniass.ci. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.it.mniass.ci.
@       IN  MX 10   mail.it.mniass.ci.
@       IN  A       192.168.100.35
ns1     IN  A       192.168.100.35
www     IN  A       192.168.100.35
mail    IN  A       192.168.100.35
portail IN  CNAME   www.it.mniass.ci.
EOF
pct exec 235 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone it.mniass.ci /etc/bind/zones/db.it.mniass.ci && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 236 : Zone "rh.mniass.ci" (192.168.100.36) ---
configure_authoritative_options 236
pct exec 236 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "rh.mniass.ci" {
    type master;
    file "/etc/bind/zones/db.rh.mniass.ci";
};
EOF
pct exec 236 -- tee /etc/bind/zones/db.rh.mniass.ci >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.rh.mniass.ci. admin.rh.mniass.ci. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.rh.mniass.ci.
@       IN  MX 10   mail.rh.mniass.ci.
@       IN  A       192.168.100.36
ns1     IN  A       192.168.100.36
www     IN  A       192.168.100.36
mail    IN  A       192.168.100.36
portail IN  CNAME   www.rh.mniass.ci.
EOF
pct exec 236 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone rh.mniass.ci /etc/bind/zones/db.rh.mniass.ci && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 237 : Zone "it.mthiongane.gn" (192.168.100.37) ---
configure_authoritative_options 237
pct exec 237 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "it.mthiongane.gn" {
    type master;
    file "/etc/bind/zones/db.it.mthiongane.gn";
};
EOF
pct exec 237 -- tee /etc/bind/zones/db.it.mthiongane.gn >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.it.mthiongane.gn. admin.it.mthiongane.gn. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.it.mthiongane.gn.
@       IN  MX 10   mail.it.mthiongane.gn.
@       IN  A       192.168.100.37
ns1     IN  A       192.168.100.37
www     IN  A       192.168.100.37
mail    IN  A       192.168.100.37
portail IN  CNAME   www.it.mthiongane.gn.
EOF
pct exec 237 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone it.mthiongane.gn /etc/bind/zones/db.it.mthiongane.gn && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# --- CT 238 : Zone "rh.mthiongane.gn" (192.168.100.38) ---
configure_authoritative_options 238
pct exec 238 -- tee /etc/bind/named.conf.local >/dev/null << 'EOF'
zone "rh.mthiongane.gn" {
    type master;
    file "/etc/bind/zones/db.rh.mthiongane.gn";
};
EOF
pct exec 238 -- tee /etc/bind/zones/db.rh.mthiongane.gn >/dev/null << 'EOF'
$TTL 86400
@   IN  SOA ns1.rh.mthiongane.gn. admin.rh.mthiongane.gn. (
            2026102701 3600 1800 604800 86400 )

@       IN  NS      ns1.rh.mthiongane.gn.
@       IN  MX 10   mail.rh.mthiongane.gn.
@       IN  A       192.168.100.38
ns1     IN  A       192.168.100.38
www     IN  A       192.168.100.38
mail    IN  A       192.168.100.38
portail IN  CNAME   www.rh.mthiongane.gn.
EOF
pct exec 238 -- bash -c "chown -R bind:bind /etc/bind/zones && named-checkconf && named-checkzone rh.mthiongane.gn /etc/bind/zones/db.rh.mthiongane.gn && systemctl restart named && systemctl enable named >/dev/null 2>&1"

# ==============================================================================
# 9. CONFIGURATION DU CLIENT / RÉSOLVEUR RÉCURSIF (CT 250 : dns-client - 192.168.100.50)
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 9. CONFIGURATION DU CLIENT / RÉSOLVEUR (CT 250 : dns-client - ${IP_CLIENT})"
echo "=============================================================================="

pct exec 250 -- tee /etc/bind/named.conf.options >/dev/null << 'EOF'
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-recursion { any; };
    allow-query { any; };
    dnssec-validation no;
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF

pct exec 250 -- tee /usr/share/dns/root.hints >/dev/null << 'EOF'
; Fichier Root Hints personnalisé pointant vers notre serveur Racine privé (Groupe D : CT 201 - 192.168.100.10)
.                        3600000      NS    D.ROOT-SERVERS.NET.
D.ROOT-SERVERS.NET.      3600000      A     192.168.100.10
EOF

pct exec 250 -- bash -c "
    named-checkconf
    systemctl restart named
    systemctl enable named >/dev/null 2>&1
    echo 'nameserver 127.0.0.1' > /etc/resolv.conf
"

# ==============================================================================
# 10. ORGANISATION PROXMOX VE : POOLS, UTILISATEURS (@pve), ACLs, TAGS & NOTES
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 10. ORGANISATION PROXMOX VE (POOLS, COMPTES @pve, TAGS, NOTES & STARTUP)"
echo "=============================================================================="

# --- 10.1 Création des 5 Resource Pools ---
declare -a POOLS=(
    "pool-dns-core|Coeur DNS (Racine, Client Resolveur, Template Base)"
    "pool-mbarry-ma|Branche DNS .ma — Administrateur: mbarry@pve"
    "pool-odiop-ml|Branche DNS .ml — Administrateur: odiop@pve"
    "pool-mniass-ci|Branche DNS .ci — Administrateur: mniass@pve"
    "pool-mthiongane-gn|Branche DNS .gn — Administrateur: mthiongane@pve"
)

for entry in "${POOLS[@]}"; do
    IFS='|' read -r POOL_ID POOL_COMMENT <<< "$entry"
    if ! pveum pool list 2>/dev/null | grep -qw "$POOL_ID"; then
        pveum pool add "$POOL_ID" --comment "$POOL_COMMENT"
    else
        pveum pool modify "$POOL_ID" --comment "$POOL_COMMENT" 2>/dev/null || true
    fi
done

# --- 10.2 Affectation des 19 Conteneurs (200..250) dans leurs Pools respectifs ---
pvesh set /pools/pool-dns-core      --vms "200,201,250"
pvesh set /pools/pool-mbarry-ma     --vms "211,221,231,232"
pvesh set /pools/pool-odiop-ml      --vms "212,222,233,234"
pvesh set /pools/pool-mniass-ci     --vms "213,223,235,236"
pvesh set /pools/pool-mthiongane-gn --vms "214,224,237,238"
echo "[OK] 5 Resource Pools créés et 19 conteneurs classés."

# --- 10.3 Création des 4 Utilisateurs Proxmox (@pve) & Délégation RBAC ---
declare -a ADMINS=(
    "mbarry|pool-mbarry-ma|Administrateur Branche .ma (mbarry.ma)"
    "odiop|pool-odiop-ml|Administrateur Branche .ml (odiop.ml)"
    "mniass|pool-mniass-ci|Administrateur Branche .ci (mniass.ci)"
    "mthiongane|pool-mthiongane-gn|Administrateur Branche .gn (mthiongane.gn)"
)

for entry in "${ADMINS[@]}"; do
    IFS='|' read -r USERNAME POOL_ID COMMENT <<< "$entry"
    if ! pveum user list 2>/dev/null | grep -qw "${USERNAME}@pve"; then
        pveum user add "${USERNAME}@pve" --password "$CT_PASS" --comment "$COMMENT" --enable 1
    else
        pveum user modify "${USERNAME}@pve" --comment "$COMMENT" --enable 1
        printf "%s\n%s\n" "$CT_PASS" "$CT_PASS" | pveum passwd "${USERNAME}@pve" >/dev/null 2>&1 || true
    fi
    # Droits d'administration complets (PVEVMAdmin) sur son propre Pool
    pveum acl modify "/pool/${POOL_ID}" --users "${USERNAME}@pve" --roles PVEVMAdmin
    # Droits de lecture (PVEAuditor) sur le Pool Coeur DNS et le noeud pve
    pveum acl modify "/pool/pool-dns-core" --users "${USERNAME}@pve" --roles PVEAuditor
    pveum acl modify "/nodes/pve" --users "${USERNAME}@pve" --roles PVEAuditor
done
echo "[OK] 4 comptes @pve (mot de passe: ${CT_PASS}) configurés avec délégation RBAC."

# --- 10.4 Configuration des Tags, Ordre de démarrage et Fiches Notes Markdown ---
pct set 200 --tags "template;core" --description "# CT 200 — dns-base (Template LXC)
- **Rôle :** Image de base Debian 12 pré-équipée de BIND9 et dnsutils
- **Pool :** pool-dns-core"

pct set 201 --tags "root;core" --startup "order=1,up=2" --description "# CT 201 — dns-root (Serveur Racine '.')
- **IP :** 192.168.100.10/24 (vmbr1)
- **Zone Maître :** . (/etc/bind/zones/db.root)
- **Récursion :** non (Autorité pure)
- **Délégations (ccTLD) :** .ma (.11), .ml (.12), .ci (.13), .gn (.14)"

# Tags & Notes ccTLD (order=2)
pct set 211 --tags "cctld;ma" --startup "order=2,up=2" --description "# CT 211 — dns-cctld-ma (Serveur ccTLD .ma)
- **IP :** 192.168.100.11/24 | **Zone Maître :** ma
- **Délégation :** mbarry.ma -> 192.168.100.21 (CT 221)
- **Admin délégué :** mbarry@pve (pool-mbarry-ma)"

pct set 212 --tags "cctld;ml" --startup "order=2,up=2" --description "# CT 212 — dns-cctld-ml (Serveur ccTLD .ml)
- **IP :** 192.168.100.12/24 | **Zone Maître :** ml
- **Délégation :** odiop.ml -> 192.168.100.22 (CT 222)
- **Admin délégué :** odiop@pve (pool-odiop-ml)"

pct set 213 --tags "cctld;ci" --startup "order=2,up=2" --description "# CT 213 — dns-cctld-ci (Serveur ccTLD .ci)
- **IP :** 192.168.100.13/24 | **Zone Maître :** ci
- **Délégation :** mniass.ci -> 192.168.100.23 (CT 223)
- **Admin délégué :** mniass@pve (pool-mniass-ci)"

pct set 214 --tags "cctld;gn" --startup "order=2,up=2" --description "# CT 214 — dns-cctld-gn (Serveur ccTLD .gn)
- **IP :** 192.168.100.14/24 | **Zone Maître :** gn
- **Délégation :** mthiongane.gn -> 192.168.100.24 (CT 224)
- **Admin délégué :** mthiongane@pve (pool-mthiongane-gn)"

# Tags & Notes Niveau 1 (order=3)
pct set 221 --tags "niv1;ma" --startup "order=3,up=2" --description "# CT 221 — dns-mbarry-ma (Niveau 1 : mbarry.ma)
- **IP :** 192.168.100.21/24 | **Zone Maître :** mbarry.ma
- **Délégations Niveau 2 :** it.mbarry.ma (.31 / CT 231), rh.mbarry.ma (.32 / CT 232)
- **Admin délégué :** mbarry@pve (pool-mbarry-ma)"

pct set 222 --tags "niv1;ml" --startup "order=3,up=2" --description "# CT 222 — dns-odiop-ml (Niveau 1 : odiop.ml)
- **IP :** 192.168.100.22/24 | **Zone Maître :** odiop.ml
- **Délégations Niveau 2 :** it.odiop.ml (.33 / CT 233), rh.odiop.ml (.34 / CT 234)
- **Admin délégué :** odiop@pve (pool-odiop-ml)"

pct set 223 --tags "niv1;ci" --startup "order=3,up=2" --description "# CT 223 — dns-mniass-ci (Niveau 1 : mniass.ci)
- **IP :** 192.168.100.23/24 | **Zone Maître :** mniass.ci
- **Délégations Niveau 2 :** it.mniass.ci (.35 / CT 235), rh.mniass.ci (.36 / CT 236)
- **Admin délégué :** mniass@pve (pool-mniass-ci)"

pct set 224 --tags "niv1;gn" --startup "order=3,up=2" --description "# CT 224 — dns-mthiongane-gn (Niveau 1 : mthiongane.gn)
- **IP :** 192.168.100.24/24 | **Zone Maître :** mthiongane.gn
- **Délégations Niveau 2 :** it.mthiongane.gn (.37 / CT 237), rh.mthiongane.gn (.38 / CT 238)
- **Admin délégué :** mthiongane@pve (pool-mthiongane-gn)"

# Tags & Notes Niveau 2 / Feuilles (order=4)
pct set 231 --tags "niv2;feuille;it;ma" --startup "order=4,up=2" --description "# CT 231 — dns-it-mbarry-ma (Feuille Niveau 2 : it.mbarry.ma)
- **IP :** 192.168.100.31/24 | **Zone Maître :** it.mbarry.ma
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 232 --tags "niv2;feuille;rh;ma" --startup "order=4,up=2" --description "# CT 232 — dns-rh-mbarry-ma (Feuille Niveau 2 : rh.mbarry.ma)
- **IP :** 192.168.100.32/24 | **Zone Maître :** rh.mbarry.ma
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 233 --tags "niv2;feuille;it;ml" --startup "order=4,up=2" --description "# CT 233 — dns-it-odiop-ml (Feuille Niveau 2 : it.odiop.ml)
- **IP :** 192.168.100.33/24 | **Zone Maître :** it.odiop.ml
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 234 --tags "niv2;feuille;rh;ml" --startup "order=4,up=2" --description "# CT 234 — dns-rh-odiop-ml (Feuille Niveau 2 : rh.odiop.ml)
- **IP :** 192.168.100.34/24 | **Zone Maître :** rh.odiop.ml
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 235 --tags "niv2;feuille;it;ci" --startup "order=4,up=2" --description "# CT 235 — dns-it-mniass-ci (Feuille Niveau 2 : it.mniass.ci)
- **IP :** 192.168.100.35/24 | **Zone Maître :** it.mniass.ci
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 236 --tags "niv2;feuille;rh;ci" --startup "order=4,up=2" --description "# CT 236 — dns-rh-mniass-ci (Feuille Niveau 2 : rh.mniass.ci)
- **IP :** 192.168.100.36/24 | **Zone Maître :** rh.mniass.ci
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 237 --tags "niv2;feuille;it;gn" --startup "order=4,up=2" --description "# CT 237 — dns-it-mthiongane-gn (Feuille Niveau 2 : it.mthiongane.gn)
- **IP :** 192.168.100.37/24 | **Zone Maître :** it.mthiongane.gn
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 238 --tags "niv2;feuille;rh;gn" --startup "order=4,up=2" --description "# CT 238 — dns-rh-mthiongane-gn (Feuille Niveau 2 : rh.mthiongane.gn)
- **IP :** 192.168.100.38/24 | **Zone Maître :** rh.mthiongane.gn
- **Enregistrements :** www (A), mail (A), portail (CNAME), MX 10"

pct set 250 --tags "client;resolver;core" --startup "order=5,up=2" --description "# CT 250 — dns-client (Client & Résolveur Récursif)
- **IP :** 192.168.100.50/24 | **Récursion :** oui
- **Root Hints :** /usr/share/dns/root.hints -> 192.168.100.10 (CT 201)"

echo "[OK] Tags visuels, Notes Markdown et Ordre de démarrage (order=1..5) appliqués."

# ==============================================================================
# 11. BATTERIE DE TESTS AUTOMATISÉS (DÉLÉGATION +TRACE & RÉCURSION SUR LES 18 CTs)
# ==============================================================================
echo ""
echo "=============================================================================="
echo " 11. BATTERIE DE TESTS AUTOMATISÉS (DÉLÉGATION +TRACE & RÉCURSION)"
echo "=============================================================================="

echo "--- [TEST A] Trace complète depuis la Racine (@${IP_ROOT}) pour www.it.mbarry.ma ---"
pct exec 250 -- dig @"${IP_ROOT}" www.it.mbarry.ma +trace +nodnssec

echo ""
echo "--- [TEST B] Trace complète depuis la Racine (@${IP_ROOT}) pour www.rh.odiop.ml ---"
pct exec 250 -- dig @"${IP_ROOT}" www.rh.odiop.ml +trace +nodnssec

echo ""
echo "--- [TEST C] Trace complète depuis la Racine (@${IP_ROOT}) pour www.it.mniass.ci ---"
pct exec 250 -- dig @"${IP_ROOT}" www.it.mniass.ci +trace +nodnssec

echo ""
echo "--- [TEST D] Trace complète depuis la Racine (@${IP_ROOT}) pour www.rh.mthiongane.gn ---"
pct exec 250 -- dig @"${IP_ROOT}" www.rh.mthiongane.gn +trace +nodnssec

echo ""
echo "--- [TEST E] Tableau récapitulatif de résolution sur les 18 Conteneurs LXC ---"
printf "%-30s | %-6s | %-18s | %-30s | %-8s\n" "FQDN TESTÉ" "TYPE" "CT INTERROGÉ (IP)" "RÉPONSE OBTENUE" "STATUT"
printf "%-30s-+-%-6s-+-%-18s-+-%-30s-+-%-8s\n" "------------------------------" "------" "------------------" "------------------------------" "--------"

TEST_CASES=(
    ".:NS:${IP_ROOT}"
    "ma:NS:${IP_MA}"
    "ml:NS:${IP_ML}"
    "ci:NS:${IP_CI}"
    "gn:NS:${IP_GN}"
    "mbarry.ma:NS:${IP_MBARRY}"
    "odiop.ml:NS:${IP_ODIOP}"
    "mniass.ci:NS:${IP_MNIASS}"
    "mthiongane.gn:NS:${IP_MTHIONGANE}"
    "it.mbarry.ma:NS:${IP_IT_MBARRY}"
    "rh.mbarry.ma:NS:${IP_RH_MBARRY}"
    "it.odiop.ml:NS:${IP_IT_ODIOP}"
    "rh.odiop.ml:NS:${IP_RH_ODIOP}"
    "it.mniass.ci:NS:${IP_IT_MNIASS}"
    "rh.mniass.ci:NS:${IP_RH_MNIASS}"
    "it.mthiongane.gn:NS:${IP_IT_MTHIONGANE}"
    "rh.mthiongane.gn:NS:${IP_RH_MTHIONGANE}"
    "www.mbarry.ma:A:${IP_CLIENT}"
    "mail.odiop.ml:A:${IP_CLIENT}"
    "www.mniass.ci:A:${IP_CLIENT}"
    "www.mthiongane.gn:A:${IP_CLIENT}"
    "www.it.mbarry.ma:A:${IP_CLIENT}"
    "portail.rh.mbarry.ma:A:${IP_CLIENT}"
    "www.it.odiop.ml:A:${IP_CLIENT}"
    "www.rh.odiop.ml:A:${IP_CLIENT}"
    "www.it.mniass.ci:A:${IP_CLIENT}"
    "mail.rh.mniass.ci:A:${IP_CLIENT}"
    "www.it.mthiongane.gn:A:${IP_CLIENT}"
    "portail.rh.mthiongane.gn:A:${IP_CLIENT}"
    "it.mbarry.ma:MX:${IP_CLIENT}"
    "rh.mthiongane.gn:MX:${IP_CLIENT}"
)

PASS_COUNT=0
FAIL_COUNT=0

for tc in "${TEST_CASES[@]}"; do
    IFS=':' read -r FQDN QTYPE SRV <<< "$tc"
    RES=$(pct exec 250 -- dig @"$SRV" "$FQDN" "$QTYPE" +short +time=2 +tries=2 | tr '\n' ' ' | sed 's/ $//')
    if [ -n "$RES" ]; then
        STATUS="OK"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        RES="AUCUNE RÉPONSE"
        STATUS="ÉCHEC"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    printf "%-30s | %-6s | %-18s | %-30s | %-8s\n" "$FQDN" "$QTYPE" "$SRV" "$RES" "$STATUS"
done

echo ""
echo "=============================================================================="
echo " BILAN FINAL : ${PASS_COUNT} tests réussis / $((PASS_COUNT + FAIL_COUNT)) exécutés (Échecs : ${FAIL_COUNT})"
echo "=============================================================================="
