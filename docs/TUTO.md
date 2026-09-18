# TUTO — image bootc perso, de A à Z (doc unique)

> Remplace : `tuto-bootc`, `tuto-saveurs`, `tuto-complet` (supprimés).
> Reste à part : `memo-bootc` (aide-mémoire commandes).

## 1. Le concept (à comprendre une fois)

Un système **bootc** ne se met pas à jour paquet par paquet : il **change
d'image complète**, comme on change de version d'appli.

- `/usr` (système) = **lecture seule**. `sudo dnf install` dessus =
  refusé ou perdu au reboot suivant.
- `/etc` (configs) et `/var` (données) = **persistants**. Tes fichiers
  et réglages survivent aux upgrades.
- Chaque image = un **déploiement**. GRUB garde l'ancien : si le
  nouveau ne boote pas, tu redémarres sur l'ancien (**rollback**).

On ne « répare » jamais le système en place, on **bascule** vers une
image qui marche.

## 2. Voir l'état — `bootc status`

```
bootc status
```

- `booted` = ce qui tourne. `staged` = prêt pour le prochain reboot.
  `rollback` = le parachute.
- Réflexe : avant ET après chaque opération.

## 3. Mettre à jour

**Image distante (quay.io, GHCR) :**
```bash
sudo bootc upgrade --check
sudo bootc upgrade
reboot
```

**Équivalent `dnf update --refresh` (image perso) :** pas d'update en
place — rebuild + switch :
```bash
cd /mnt/DATA/Bootc   # ou le dossier du projet
./build.sh localhost/mon-bootc:latest   # base + RPM frais (--pull=newer)
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

**Mise à jour légère (image déjà sur GHCR) :** pas de build, juste :
```bash
sudo bootc switch ghcr.io/swam-web/mon-bootc:base-LECODE_RECENT
reboot
```
`LECODE_RECENT` : dépôt GitHub → **Packages** → `mon-bootc` →
**Tags** → le plus récent de ta saveur.

À part, comme sur Fedora : `flatpak update`, et dans chaque toolbox
`sudo dnf update`.

## 4. Revenir en arrière — `bootc rollback` (par cœur)

```bash
sudo bootc rollback
reboot
```

Ou au boot : menu GRUB → entrée précédente. Règles :
- Jamais 2 upgrades/switch sans reboot entre les deux (un seul
  déploiement précédent gardé).
- Après un rollback qui sauve : `bootc status` pour confirmer.
- Tester le rollback UNE fois à blanc pour savoir le faire le jour J.

## 5. Changer d'image — `bootc switch`

```bash
sudo bootc switch quay.io/ton/image:tag
reboot
```

**Cas `localhost/` (dev local) :** `bootc upgrade` cherche un registre
local inexistant (`pinging container registry localhost/v2`) — normal.
Toujours `switch --transport containers-storage` (voir §3).

**Vers une VM** (le `switch` lit le stockage LOCAL) : construire sur le
host, transférer, charger dans la VM :
```bash
# host :
sudo podman save localhost/mon-bootc:latest -o /mnt/DATA/mon-bootc.tar
# transfert : scp, ou sans SSH : host `python3 -m http.server 8000`
#   dans /mnt/DATA, puis VM `curl -O http://192.168.122.1:8000/mon-bootc.tar`
# VM :
sudo podman load -i ~/mon-bootc.tar
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

## 6. Re-baker un pilote plus tard (sans réinstaller)

Ajoute l'étape au Containerfile, rebuild, transfère, puis `switch`
(§3/§5). `/etc` et `/var` survivent, seul `/usr` est remplacé.

## 6b. Changer de version Fedora (ex. 44 → 45/46) le jour J

Les endroits avec la version en dur : `FROM ...:44` + URLs COPR
(`.../fedora-44/...`). Les dépôts RPMFusion suivent tout seuls
(macro `%fedora`).

Marche à suivre :
```bash
cd /mnt/DATA/Bootc/Github
git checkout base
# édite Containerfile : FROM ...:44 → :45 + URLs COPR fedora-44 → fedora-45
git add -A && git commit -m "fedora 45" && git push origin base
# 2. Rebuild + test VM obligatoire (nouveau kernel, nouveaux paquets)
./build.sh localhost/mon-bootc:base base
# 3. Si VM saine : transfert + switch + reboot (§3/§5)
#    + merge base vers les saveurs utilisées, push (CI), switch machines
# 4. Si cassé : rollback (§4), on reste en 44 le temps que ça mûrisse
```

Ne jamais bumper en aveugle : les COPR tiers (kernel, addons)
doivent avoir publié pour la nouvelle version, sinon build rouge.

## 7. Applis : jamais `dnf` sur le host

| Besoin | Où |
|---|---|
| Graphique | `flatpak install flathub <nom>` |
| CLI / dev | `toolbox` / `distrobox` + dnf dedans |
| Binaire perso | `~/.local/bin` |
| Service système | baké dans l'image + rebuild + switch |

## 8. Drivers

**Nvidia — 2 voies.** Le kmod doit matcher `uname -r` exactement,
sinon écran noir.
- *Baké* (saveur `nvidia`) : rebuildé avec le kernel, jamais de
  désync. Recommandé si une machine = une saveur.
- *Post-install* (`install-nvidia-host.sh`) : `bootc usr-overlay`
  (transitoire !) + akmod compilé contre le kernel qui tourne +
  `akmods` activé (rebuild auto aux changements de kernel).
  À refaire après chaque `bootc upgrade`. Secure Boot OFF ou clé MOK.
  Vérif : `nvidia-smi`.

**AMD ROCm** (`install-rocm-host.sh`) : userspace seul, pas de kmod
(amdgpu in-kernel) — aucun risque de désync. Vérif : `rocminfo`.

**WiFi MT7927** : toujours baké (sans lui, pas de réseau au 1er boot).
Kernel + réglages CachyOS : **intouchables**.

**Imprimante HP** : bakée si saveur `printer`, sinon
`install-hplip-host.sh`. Test : `hp-check -r`.

## 9. Saveurs (1 recette, 4 images)

| Branche / tag | Contenu | Pour |
|---|---|---|
| `base` | kernel, MT7927, GNOME, codecs, outils | partout, VM |
| `nvidia` | + driver Nvidia baké | host RTX |
| `rocm` | + userspace AMD | PC AMD |
| `printer` | + hplip/gui | PC imprimante |

Le fichier `FLAVOR` (1 mot) dit quoi builder :
```bash
./build.sh localhost/mon-bootc:nvidia nvidia
```

**CI GitHub :** push sur une branche ⇒ build de SA saveur sur le
runner maison ⇒ image sur GHCR (`mon-bootc:<saveur>-<sha>`).
Suivi : onglet **Actions** (vert/rouge). Règle : on bosse sur
`base`, `git merge base` vers les saveurs, jamais l'inverse.

**Runner :** conteneur `gh-runner` (`--privileged`), 1 job à la fois.
Token **d'enregistrement** page Add runner (jamais le PAT).
Logs : `sudo podman logs -f gh-runner`.

## 10. Diagnostiquer

```
journalctl -b -1 -p err | tail -20
journalctl -b -1 | grep -i -E "fail|nvidia|drm|gdm" | tail -30
systemctl --failed
```

- Noir après update Nvidia : déploiement précédent → relance script
  driver → reboot.
- Build CI rouge : lire le **bas** du step rouge.
- Méthode : 1 hypothèse, 1 changement, 1 reboot, vérifier.

## 11. Règles d'or

> VM d'abord, host ensuite.
> 1 changement = 1 reboot = 1 test.
> `bootc status` avant et après. Rollback = parachute.
> Build local : `./build.sh`. Recette : jamais de secret dedans.

## 12. Anti-sèches projet

- Build : `./build.sh [image] [saveur]` (VM, `base` par défaut).
- ISO : `./build.sh` → `output/*.iso`, tester en VM d'abord.
- Drivers host : `install-nvidia-host.sh` / `install-rocm-host.sh` (jamais en VM).
- Applis : `install-flatpaks.sh` (`WITH_GAMING=1` pour jeux).
- Imprimante : `install-hplip-host.sh`.
- Test VM : voir `Test bootc.txt`.
