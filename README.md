# Infrastructure DNS Hiérarchique BIND9 sous Proxmox VE (LXC)

Projet d'administration réseau : déploiement et interconnexion d'une infrastructure DNS complète et distribuée avec **BIND9** sous **19 conteneurs LXC Proxmox VE**.

Le serveur racine privé du groupe est désigné sous le nom officiel **`D.ROOT-SERVERS.NET.`** (`192.168.100.10`) et interconnecté avec les racines des autres groupes d'étudiants (total de 11 TLD actifs).

---

## 📌 Vue d'ensemble de l'Infrastructure

- **Hôte Proxmox VE :** `10.153.4.186`
- **Réseau interne (Bridge dédié) :** `vmbr1` (`192.168.100.0/24`)
- **Serveur Racine Privé (Groupe D) :** `CT 201` (`192.168.100.10`) — Zone `.` (`D.ROOT-SERVERS.NET.`)
- **4 ccTLD (Niveau TLD) :** `.ma`, `.ml`, `.ci`, `.gn` (`192.168.100.11` à `.14`)
- **4 Domaines (Niveau 1 / SLD) :** `mbarry.ma`, `odiop.ml`, `mniass.ci`, `mthiongane.gn` (`192.168.100.21` à `.24`)
- **8 Feuilles Départementales (Niveau 2) :** `it.<domaine>` et `rh.<domaine>` (`192.168.100.31` à `.38`)
- **Template de clonage :** `CT 200` (`dns-base` — Debian 12 + BIND9 + dnsutils)
- **Résolution autonome :** Fichier `/usr/share/dns/root.hints` personnalisé déployé sur chaque nœud (plus besoin de résolveur dédié).

---

## 🌳 Arbre Hiérarchique DNS

```text
                     [ NIVEAU 0 : RACINE '.' — CT 201 : 192.168.100.10 ]
                               Nom NS : D.ROOT-SERVERS.NET.
                                             │
        ┌────────────────────────┬───────────┴───────────┬────────────────────────┐
        │                        │                       │                        │
   [ Zone .ma ]             [ Zone .ml ]            [ Zone .ci ]             [ Zone .gn ]
   CT 211 (.11)             CT 212 (.12)            CT 213 (.13)             CT 214 (.14)
   NS: ns1.ma.              NS: ns1.ml.             NS: ns1.ci.              NS: ns1.gn.
        │                        │                       │                        │
  [ mbarry.ma ]            [ odiop.ml ]            [ mniass.ci ]          [ mthiongane.gn ]
   CT 221 (.21)             CT 222 (.22)            CT 223 (.23)             CT 224 (.24)
     /      \                 /      \                /      \                 /      \
  [it]      [rh]           [it]      [rh]          [it]      [rh]           [it]      [rh]
 CT 231    CT 232         CT 233    CT 234        CT 235    CT 236         CT 237    CT 238
  (.31)     (.32)          (.33)     (.34)         (.35)     (.36)          (.37)     (.38)
```

---

## 📋 Plan d'Adressage et Rôles des Conteneurs

| VMID | Nom du Conteneur | Niveau / Rôle | Zone DNS | Adresse IP (`vmbr1`) | Pool Proxmox / Admin |
| :---: | :--- | :--- | :--- | :---: | :--- |
| **200** | `dns-base` | Template de base | - | `192.168.100.200/24` | `pool-dns-core` (`root`) |
| **201** | `dns-root` | Racine `.` | `.` (`D.ROOT`) | `192.168.100.10/24` | `pool-dns-core` (`root`) |
| **211** | `dns-cctld-ma` | ccTLD Maroc | `ma.` | `192.168.100.11/24` | `pool-mbarry-ma` (`mbarry@pve`) |
| **212** | `dns-cctld-ml` | ccTLD Mali | `ml.` | `192.168.100.12/24` | `pool-odiop-ml` (`odiop@pve`) |
| **213** | `dns-cctld-ci` | ccTLD Côte d'Ivoire | `ci.` | `192.168.100.13/24` | `pool-mniass-ci` (`mniass@pve`) |
| **214** | `dns-cctld-gn` | ccTLD Guinée | `gn.` | `192.168.100.14/24` | `pool-mthiongane-gn` (`mthiongane@pve`) |
| **221** | `dns-mbarry-ma` | Niveau 1 (SLD) | `mbarry.ma.` | `192.168.100.21/24` | `pool-mbarry-ma` (`mbarry@pve`) |
| **222** | `dns-odiop-ml` | Niveau 1 (SLD) | `odiop.ml.` | `192.168.100.22/24` | `pool-odiop-ml` (`odiop@pve`) |
| **223** | `dns-mniass-ci` | Niveau 1 (SLD) | `mniass.ci.` | `192.168.100.23/24` | `pool-mniass-ci` (`mniass@pve`) |
| **224** | `dns-mthiongane-gn`| Niveau 1 (SLD) | `mthiongane.gn.` | `192.168.100.24/24` | `pool-mthiongane-gn` (`mthiongane@pve`) |
| **231** | `dns-it-mbarry-ma` | Niveau 2 (Feuille) | `it.mbarry.ma.` | `192.168.100.31/24` | `pool-mbarry-ma` (`mbarry@pve`) |
| **232** | `dns-rh-mbarry-ma` | Niveau 2 (Feuille) | `rh.mbarry.ma.` | `192.168.100.32/24` | `pool-mbarry-ma` (`mbarry@pve`) |
| **233** | `dns-it-odiop-ml` | Niveau 2 (Feuille) | `it.odiop.ml.` | `192.168.100.33/24` | `pool-odiop-ml` (`odiop@pve`) |
| **234** | `dns-rh-odiop-ml` | Niveau 2 (Feuille) | `rh.odiop.ml.` | `192.168.100.34/24` | `pool-odiop-ml` (`odiop@pve`) |
| **235** | `dns-it-mniass-ci` | Niveau 2 (Feuille) | `it.mniass.ci.` | `192.168.100.35/24` | `pool-mniass-ci` (`mniass@pve`) |
| **236** | `dns-rh-mniass-ci` | Niveau 2 (Feuille) | `rh.mniass.ci.` | `192.168.100.36/24` | `pool-mniass-ci` (`mniass@pve`) |
| **237** | `dns-it-mthiongane-gn`| Niveau 2 (Feuille) | `it.mthiongane.gn.` | `192.168.100.37/24` | `pool-mthiongane-gn` (`mthiongane@pve`) |
| **238** | `dns-rh-mthiongane-gn`| Niveau 2 (Feuille) | `rh.mthiongane.gn.` | `192.168.100.38/24` | `pool-mthiongane-gn` (`mthiongane@pve`) |
| **250** | `dns-client` | Client / Résolveur | - | `192.168.100.50/24` | `pool-dns-core` (`root`) |

---

## 🌐 Interconnexions Multi-Groupes (11 TLD)

Le fichier `/etc/bind/zones/db.root` sur `CT 201` déclare l'ensemble des délégations TLD de la classe :

1. **Notre Groupe (`vmbr1`) :**
   - `.ma` (`192.168.100.11`), `.ml` (`192.168.100.12`), `.ci` (`192.168.100.13`), `.gn` (`192.168.100.14`)
2. **Groupe 1 (Même Proxmox `vmbr0` - Racine `10.153.4.224`) :**
   - `.ba` (`10.153.4.225` &rarr; `ucad.ba`)
   - `.diallo` (`10.153.4.226` &rarr; `uadb.diallo`)
   - `.cisse` (`10.153.4.247` &rarr; `retel.cisse`)
   - `.diasse` (`10.153.4.246` &rarr; `lab.diasse`)
3. **Groupe 3 (Autre serveur Proxmox physique - `10.153.4.0/24`) :**
   - `.sn` (`10.153.4.229` &rarr; `ucad.sn`, `edu.sn`)
   - `.org` (`10.153.4.230` &rarr; `ucad.org`, `edu.org`)
   - `.com` (`10.153.4.231` &rarr; `ucad.com`, `edu.com`)

---

## 🚀 Déploiement et Démarrage

### Déploiement automatique
Le script `deploy_ct_dns.sh` configure l'intégralité de la chaîne (création réseau, pools, utilisateurs RBAC `@pve`, conteneurs LXC, fichiers BIND9, zones et ACLs) :

```bash
chmod +x deploy_ct_dns.sh
./deploy_ct_dns.sh
```

### Démarrage ordonné de tous les conteneurs
```bash
for id in $(pct list | awk 'NR>1 && $1!=200 {print $1}'); do pct start $id; done
```

---

## 🧪 Commandes de Test et Validation

### 1. Depuis la console de n'importe quel conteneur (ex: CT 221 ou CT 231)
```bash
# Vérifier la racine locale
dig . NS +short
dig D.ROOT-SERVERS.NET +short

# Résolution des sous-domaines (Niveau 2)
dig www.it.mbarry.ma +short
dig www.rh.odiop.ml +short

# Résolution inter-groupes
dig www.ucad.ba +short
dig www.ucad.sn +short

# Ping direct par FQDN
ping -c 2 www.it.mthiongane.gn

# Visualiser la chaîne de délégation itérative (4 sauts)
dig www.it.mbarry.ma +trace
```

### 2. Depuis un PC externe (via redirection Proxmox 10.153.4.186:53)
```powershell
nslookup D.ROOT-SERVERS.NET 10.153.4.186
nslookup www.it.mbarry.ma 10.153.4.186
nslookup www.ucad.ba 10.153.4.186
```

---

## 📁 Contenu du Dépôt

- `deploy_ct_dns.sh` : Script Bash principal automatisant le déploiement complet des 19 CTs sous Proxmox.
- `Rapport_TP_DNS_Hierarchique_BIND9.pdf` : Rapport technique complet et guide de soutenance (5 pages).
- `Rapport_TP_DNS_Hierarchique_BIND9.docx` : Version éditable Word du rapport technique.
- `dns-lab/` : Dockerfile et configuration pour réplication locale allégée sur Docker.
- `start` : Script utilitaire pour démarrer tous les conteneurs LXC sur Proxmox.
