# TUTO — Image bootc perso, de A à Z

> **Remplace** : `tuto-bootc`, `tuto-saveurs`, `tuto-complet` (supprimés)
> **Complète** : `memo-bootc.html` (aide-mémoire commandes)

---

## Table des matières

1. [Le concept](#1-le-concept--comprendre-une-fois)
2. [Voir l'état — `bootc status`](#2-voir-état--bootc-status)
3. [Mettre à jour](#3-mettre-à-jour)
4. [Revenir en arrière — `bootc rollback`](#4-revenir-en-arrière--bootc-rollback)
5. [Changer d'image — `bootc switch`](#5-changer-dimage--bootc-switch)
6. [Re-baker un pilote / Changer de Fedora](#6-re-baker-un-pilote--changer-de-fedora)
7. [Applications — jamais dnf sur le host](#7-applications--jamais-dnf-sur-le-host)
8. [Drivers](#8-drivers)
9. [Saveurs (1 recette, 4 images)](#9-saveurs--1-recette-4-images)
10. [Diagnostiquer](#10-diagnostiquer)
11. [Règles d'or](#11-règles-dor)
12. [Anti-sèches projet](#12-anti-sèches-projet)

---

## 1. Le concept — comprendre une fois

Un système **bootc** ne se met pas à jour paquet par paquet : il **change d'image complète**, comme on change de version d'appli.

```
┌─────────────────────────────────────────────────────────────┐
│                    SYSTÈME BOOTC                             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│   /usr  ──── lecture seule ──── dnf install = REFUSÉ         │
│                                                               │
│   /etc  ──── persistant ─────── configs, services              │
│                                                               │
│   /var  ──── persistant ─────── données, home, opt             │
│                                                               │
│   ┌──────────────────────────────────────────────────────┐   │
│   │  DÉPLOIEMENT ACTUEL (lecture)                        │   │
│   │  noyau + drivers + apps = 1 couche atomique           │   │
│   └──────────────────────────────────────────────────────┘   │
│                          ▲                                    │
│                          │                                    │
│                    bootc switch                               │
│                          │                                    │
│   ┌──────────────────────────────────────────────────────┐   │
│   │  NOUVEAU DÉPLOIEMENT (staged)                         │   │
│   │  prêt pour le prochain reboot                         │   │
│   └──────────────────────────────────────────────────────┘   │
│                          ▲                                    │
│                          │                                    │
│                      ROLLBACK                                 │
│                    (parachute)                                │
│                                                               │
└─────────────────────────────────────────────────────────────┘

  Image = snapshot complet. On ne répare pas, on BASCULE.
```

### Règle fondamentale

| Ce que tu fais | Résultat |
|---|---|
| `sudo dnf install truc` | Perdu au reboot (sur /usr) |
| Modifier `/etc/nginx/nginx.conf` | ✅ Persiste |
| Sauvegarder dans `/home/` ou `/mnt/data/` | ✅ Persiste |
| `bootc rollback` | Retour en arrière complet |

---

## 2. Voir l'état — `bootc status`

```bash
bootc status
```

Résultat typique :

```
Deployments:
 ● ostree-image-signed:quay.io/.../mon-bootc:base
     Version: 44.20260913.0 (2026-09-13T18:22:00Z)
     Booted: yes

  ostree-image-signed:quay.io/.../mon-bootc:base
     Version: 44.20260912.0 (2026-09-12T18:22:00Z)
     Booted: no  ← ROLLBACK possible
```

| Champ | Signification |
|---|---|
| `Booted: yes` | Ce qui tourne maintenant |
| Déploiement sans `Booted` | Staged (prochain reboot) ou rollback |
| `rollback` | Le parachute — il n'y en a qu'un |

> ⚡ **Réflexe** : `bootc status` avant ET après chaque opération.

---

## 3. Mettre à jour

### Image distante (quay.io, GHCR)

```bash
sudo bootc upgrade --check     # voir sans appliquer
sudo bootc upgrade            # télécharger + stage
reboot                        # basculer
```

### Image perso (le cas de ce projet)

Pas d'update en place — rebuild + switch :

```bash
cd /mnt/DATA/Bootc/Github    # ou ton dossier projet
./build.sh localhost/mon-bootc:latest    # rebuild frais
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

### Mise à jour légère (image déjà sur GHCR)

Pas de build, juste changer de tag :

```bash
sudo bootc switch ghcr.io/swam-web/mon-bootc:base-<LE_CODE_RECENT>
reboot
```

Où trouver `LE_CODE_RECENT` :
> Dépôt GitHub → onglet **Packages** → `mon-bootc` → **Tags** → le plus récent

### À part, comme sur Fedora actuel

```bash
flatpak update                         # applis graphiques
toolbox enter → sudo dnf update        # env. dev (container)
```

---

## 4. Revenir en arrière — `bootc rollback`

```bash
sudo bootc rollback
reboot
```

Ou au boot : menu GRUB → entrée précédente.

```
  AVANT :  booted = déploiement A
  bootc rollback
  REBOOT  → booted = déploiement précédent B
```

> ⚠️ **Règles** :
> - Jamais 2 switches sans reboot entre (1 seul rollback gardé)
> - Après un rollback qui sauve : `bootc status` pour confirmer
> - **Teste le rollback UNE fois à blanc** pour connaître la manip le jour J

---

## 5. Changer d'image — `bootc switch`

```bash
sudo bootc switch quay.io/<REGISTRE>/<IMAGE>:<TAG>
reboot
```

### Cas `localhost/` (dev local) ⚠️

`bootc upgrade` avec une image `localhost/` échoue :

```
error: pinging container registry localhost/v2: ...
```

C'est normal : pas de registre local. Utiliser **switch** avec le transport explicite :

```bash
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
```

### Vers une VM (le switch lit le stockage LOCAL)

```
┌──────────────────┐                    ┌──────────────────┐
│      HOST        │                    │       VM         │
│                  │                    │                  │
│  podman save ─────┼─── transfert ────┼──► podman load   │
│                  │    (scp/http)     │                  │
│                  │                    │  bootc switch    │
│                  │                    │  --transport     │
│                  │                    │  containers-     │
│                  │                    │  storage         │
└──────────────────┘                    └──────────────────┘
```

```bash
# Sur le host :
sudo podman save localhost/mon-bootc:latest -o /mnt/DATA/mon-bootc.tar

# Transfert (au choix) :
scp /mnt/DATA/mon-bootc.tar user@vm:~/            # via SSH
# OU sans SSH :
#   host : cd /mnt/DATA && python3 -m http.server 8000
#   VM   : curl -O http://192.168.122.1:8000/mon-bootc.tar

# Dans la VM :
sudo podman load -i ~/mon-bootc.tar
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

---

## 6. Re-baker un pilote / Changer de Fedora

### Re-baker (ajouter un pilote au Containerfile)

```
  Containerfile (modifié)
       │
       ▼
  ./build.sh localhost/mon-bootc:nouveau
       │
       ▼
  bootc switch → reboot
       │
       ▼
  /usr remplacé, /etc + /var survivent
```

1. Ajouter l'étape dans le `Containerfile`
2. Rebuild, transférer, `switch` (§3/§5)
3. `/etc` et `/var` survivent — seul `/usr` est remplacé

### Changer de version Fedora (44 → 45/46)

Ce qui est « dur » dans le Containerfile :

| Élément | Exemple |
|---|---|
| FROM | `FROM quay.io/fedora/fedora-bootc:44` |
| COPR | `.../fedora-44/bieszczaders-kernel-...` |

Marche à suivre :

```bash
cd /mnt/DATA/Bootc/Github
git checkout base

# Éditer Containerfile :
#   FROM ...:44  →  FROM ...:45
#   URLs COPR → versions fedora-45

git add -A && git commit -m "fedora 45" && git push origin base

# Rebuild + test VM OBLIGATOIRE (nouveau kernel, nouveaux paquets)
./build.sh localhost/mon-bootc:base base

# Si VM saine :
#   transfert + switch + reboot (§3/§5)
#   + merge base vers les saveurs, push (CI), switch machines

# Si cassé :
#   rollback (§4), rester en 44 le temps que ça mûrisse
```

> 🚨 **Ne JAMAIS bumper en aveugle** : les COPR tiers (kernel CachyOS, addons)
> doivent avoir publié pour la nouvelle version, sinon build rouge.

---

## 7. Applications — jamais dnf sur le host

```
  ┌─────────────────────────────────────────────────────────┐
  │                    HOST (bootc)                          │
  │                                                         │
  │   /usr  = lecture seule  →  PAS dnf install            │
  │                                                         │
  │   Applis là-dessus :                                   │
  │   ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  │
  │   │  Flatpak    │  │  Toolbox /  │  │  ~/.local/   │  │
  │   │  (Flathub)  │  │  Distrobox  │  │  bin/        │  │
  │   │             │  │  (Fedora)   │  │  (Perso)     │  │
  │   └─────────────┘  └─────────────┘  └──────────────┘  │
  │                                                         │
  │   Service système = baké dans l'image (rebuild)        │
  └─────────────────────────────────────────────────────────┘
```

| Besoin | Où | Commande |
|---|---|---|
| Graphique | Flatpak (Flathub) | `flatpak install flathub <nom>` |
| CLI / dev | Toolbox / Distrobox | `toolbox enter` → `sudo dnf install` |
| Binaire perso | `~/.local/bin` | `./mon-appli` |
| Service système | Dans l'image | Rebuild + switch |

---

## 8. Drivers

### Nvidia — 2 voies

Le driver Nvidia **doit** matcher exactement `uname -r`, sinon écran noir.

```
  ┌─────────────────────────┐     ┌─────────────────────────┐
  │   VOIE A : BAKÉ         │     │   VOIE B : POST-INSTALL │
  │   (saveur nvidia)       │     │   (script hôte)         │
  │                         │     │                         │
  │   Containerfile :       │     │   install-nvidia-       │
  │   FROM + akmod-nvidia   │     │   host.sh               │
  │   compilé avec kernel   │     │   bootc usr-overlay      │
  │                         │     │   (transitoire !)        │
  │   ✅ Jamais de désync   │     │   ⚠️ À refaire après    │
  │   ✅ Rebuild = aligned  │     │     chaque upgrade      │
  │   ⚠️ Lourd (~2 Go)      │     │   ✅ Léger              │
  └─────────────────────────┘     └─────────────────────────┘
```

```bash
# Vérification :
nvidia-smi

# Secure Boot : kmods non signés clé Fedora
#   → désactiver Secure Boot OU enroller clé MOK
```

### AMD ROCm (install-rocm-host.sh)

Userspace seul, pas de kmod (amdgpu in-kernel) — **aucun risque de désync**.

```bash
rocminfo    # vérification
```

### WiFi MT7927 — toujours baké

Pas de réseau au 1er boot sans lui. Firmware + driver dans l'image.

### Imprimante HP

```
  saveur printer → hplip + hplip-gui bakés
  autre saveur  → install-hplip-host.sh (post-install)
```

Test : `hp-check -r`

> ⚠️ **Kernel CachyOS + réglages = intouchables**. Ne jamais modifier
> sans test VM préalable.

---

## 9. Saveurs (1 recette, 4 images)

```
                        ┌──────────────────────────────┐
                        │      Containerfile           │
                        │   (1 seule recette)          │
                        │   + build-args (3 flags)     │
                        └──────────┬───────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
    ┌─────────▼──────┐  ┌─────────▼──────┐  ┌─────────▼──────┐
    │   WITH_NVIDIA  │  │   WITH_ROCM    │  │  WITH_PRINTER  │
    │       =1       │  │      =1        │  │      =1        │
    └─────────┬──────┘  └─────────┬──────┘  └─────────┬──────┘
              │                    │                    │
    ┌─────────▼──────┐  ┌─────────▼──────┐  ┌─────────▼──────┐
    │    nvidia      │  │     rocm       │  │    printer     │
    │  (RTX host)    │  │   (AMD host)   │  │  (imprimante)  │
    └────────────────┘  └────────────────┘  └────────────────┘

           tous : kernel CachyOS + MT7927 + GNOME + codecs
```

| Branche | Contenu | Pour |
|---|---|---|
| `base` | kernel, MT7927, GNOME, codecs, outils | partout, VM |
| `nvidia` | + driver Nvidia baké | host RTX |
| `rocm` | + userspace AMD | PC AMD |
| `printer` | + hplip/gui | PC imprimante |

### Builder

```bash
./build.sh localhost/mon-bootc:nvidia nvidia
```

Le fichier `FLAVOR` (1 mot) dans `build/` indique la saveur par défaut.

### CI GitHub

```
  push sur branche
       │
       ▼
  ┌─────────────────────────────────────────────┐
  │  Actions (workflow build.yml)               │
  │                                             │
  │  4 jobs parallèles :                        │
  │    build-base / build-nvidia /              │
  │    build-rocm   / build-printer             │
  │                                             │
  │  → podman build → image locale             │
  │  → bootc-image-builder → ISO dans output/   │
  └─────────────────┬───────────────────────────┘
                    │
                    ▼
              ghcr.io/swam-web/mon-bootc:<saveur>-<sha>
```

> 📌 **Règle git** : bosser sur `base`, `git merge base` vers les saveurs, **jamais l'inverse**.

---

## 10. Diagnostiquer

```bash
# Erreurs du boot précédent
journalctl -b -1 -p err | tail -20

# Filtrage ciblé
journalctl -b -1 | grep -i -E "fail|nvidia|drm|gdm" | tail -30

# Services en échec
systemctl --failed
```

| Symptôme | Solution |
|---|---|
| Noir après update Nvidia | Boot sur déploiement précédent → relancer `install-nvidia-host.sh` → reboot |
| Build CI rouge | Lire le **bas** du step rouge dans les logs |
| Général | 1 hypothèse → 1 changement → 1 reboot → vérifier |

---

## 11. Règles d'or

```
  ╔═══════════════════════════════════════════════════════╗
  ║  1. VM d'abord, host ensuite                         ║
  ║  2. 1 changement = 1 reboot = 1 test                  ║
  ║  3. bootc status avant et après                      ║
  ║  4. Rollback = parachute (le tester à blanc)          ║
  ║  5. Build local : ./build.sh (jamais de secret)      ║
  ╚═══════════════════════════════════════════════════════╝
```

---

## 12. Anti-sèches projet

```bash
# Build ISO (tester en VM d'abord)
./build.sh [image] [saveur]

# Host (jamais en VM)
sudo install-nvidia-host.sh      # Nvidia
sudo install-rocm-host.sh        # AMD
sudo install-hplip-host.sh       # Imprimante
sudo install-flatpaks.sh         # Applis (+ WITH_GAMING=1)
```

Voir aussi : `docs/test-vm.md` pour la procédure complète de test en VM.

---

<p align="center"><em>Document maintenu avec soin. Bootc = la tranquillité.</em></p>
