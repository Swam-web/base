# Tuto bootc documenté — RakuOS / Fedora Atomic

## 1. Le concept (à comprendre une fois)

Un système **bootc** ne se met pas à jour paquet par paquet : il **change
d'image disque complète**, comme on change de version d'appli.

- `/usr` (système) = **lecture seule**, montée depuis l'image. `sudo dnf
  install` dessus = refusé ou perdu au reboot suivant.
- `/etc` (configs) et `/var` (données) = **persistants**, conservés d'une
  image à l'autre. Tes fichiers et réglages survivent aux upgrades.
- Chaque image téléchargée = un **déploiement**. GRUB garde l'ancien :
  si le nouveau ne boote pas, tu redémarres sur l'ancien. C'est le
  **rollback**, et c'est ça qui rend bootc sûr.

Conséquence directe : on ne « répare » jamais le système en place, on
**bascule** vers une image qui marche.

## 2. Voir l'état — `bootc status`

```
bootc status
```

Exemple de lecture :
- `booted` = image qui tourne actuellement.
- `staged` = image téléchargée, appliquée au prochain reboot.
- `rollback` = image précédente, ton parachute.

Réflexe : `bootc status` **avant et après** chaque opération. Si tu ne
sais plus où tu en es, c'est cette commande qui dit la vérité, pas ta
mémoire.

## 3. Mettre à jour — `bootc upgrade`

```
sudo bootc upgrade --check   # consulte seulement : version, taille, digest
sudo bootc upgrade           # télécharge (~Go) et prépare le déploiement
reboot                       # bascule effective
```

Pourquoi en 2 temps : le téléchargement ne touche pas au système en
cours. Tu peux continuer à travailler, rebooter quand tu veux. Si le
nouveau déploiement échoue au boot → rollback (chapitre 4).

## 4. Revenir en arrière — `bootc rollback`

```
sudo bootc rollback
reboot
```

Ou sans taper de commande : au démarrage, menu GRUB → choisir l'entrée
précédente. Règle d'hygiène : **jamais 2 upgrades sans reboot entre les
deux**, sinon tu écrases ton parachute (le rollback ne garde qu'UN
déploiement précédent).

## 5. Changer d'image — `bootc switch`

```
sudo bootc switch quay.io/ton/image:tag
reboot
```

À quoi ça sert concrètement :
- tester ta propre image perso (`localhost/mon-bootc:latest` poussée
  quelque part, ou en local via `--transport`),
- revenir à une version pinnée connue-bonne,
- changer d'édition (GNOME ↔ KDE).

`/etc` et `/var` suivent : tes users, ton réseau, tes données restent.

## 5b. Cas particulier : image `localhost/...` (dev local)

`bootc upgrade` sur une image taggée `localhost/` cherche un registre
local (`localhost/v2`) qui n'existe pas => erreur
`pinging container registry localhost/v2`. Normal, pas un bug.

Boucle de dev locale (depuis le dossier projet) :
```bash
./build.sh localhost/mon-bootc:latest
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

`upgrade` = registre distant (quay.io...). `switch` + `containers-storage`
= image construite en local. Ne jamais `upgrade` une image `localhost`.

## 5c. Équivalent `dnf update --refresh` (mettre à jour le système)

Pas d'update en place sur bootc. L'update = rebuild + switch :
```bash
./build.sh localhost/mon-bootc:latest   # --pull=newer : base + RPM frais
# transfert vers la VM (5d), puis dans la VM :
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```
À part, comme sur Fedora : `flatpak update`, et dans chaque toolbox
`sudo dnf update`.

## 5d. Transférer l'image vers une VM (le `switch` lit le stockage LOCAL)

Construire sur le host, charger dans la VM. Sur le host :
```bash
sudo podman save localhost/mon-bootc:latest -o /mnt/DATA/mon-bootc.tar
```
Transfert host → VM (au choix) :
```bash
scp /mnt/DATA/mon-bootc.tar user@IP-VM:~/
# ou sans SSH (liveuser sans mot de passe) :
# host : cd /mnt/DATA && python3 -m http.server 8000
# VM   : curl -O http://192.168.122.1:8000/mon-bootc.tar
```
Dans la VM :
```bash
sudo podman load -i ~/mon-bootc.tar
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

## 5e. Re-baker un pilote plus tard (sans réinstaller)

Besoin d'un driver dans l'image après coup (ex. Nvidia) ? Pas de
réinstall : ajoute l'étape au Containerfile, rebuild, transfère, puis :
```bash
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```
`/etc` (configs) et `/var` (données, flatpaks) survivent. Seul `/usr`
est remplacé — là où vit le driver. C'est tout l'intérêt du modèle.

## 6. Installer une appli (jamais `dnf` sur le host)

| Besoin | Pourquoi ici | Commande |
|---|---|---|
| Appli graphique | isolée, versionnée, survit aux upgrades | `flatpak install flathub <nom>` |
| Outil CLI / dev / build | container mutable avec dnf normal | `toolbox create` puis `toolbox enter` |
| Script/binaire perso | hors image, chemin user | `~/.local/bin` (+ PATH) |
| Service système | doit être baké dans l'image | Containerfile + rebuild + switch |

Le `sudo dnf install` du réflexe Debian/Fedora classique **ne marche
pas** sur bootc : `/usr` est verrouillé. Si une doc te le demande,
c'est qu'elle ne parle pas de bootc.

## 7. Installer un driver proprio (Nvidia) — les 2 voies expliquées

**Contexte du piège :** un driver kernel (kmod) doit correspondre
**exactement** au kernel qui tourne (`uname -r`). Un décalage = écran
noir. C'est arrivé quand le kmod compilé au build ne matchait plus le
kernel du 2e boot (rolling CachyOS).

**Voie A — baké dans l'image (recommandé bootc).**
Le driver voyage AVEC l'image : `bootc switch` = kernel + kmod testés
ensemble. Jamais de désync. Inconvénient : rebuild d'image à chaque
changement driver.

**Voie B — post-install sur machine prête (`install-nvidia-host.sh`).**
```bash
sudo bootc usr-overlay   # /usr inscriptible UNIQUEMENT pour ce boot
sudo ./install-nvidia-host.sh   # akmod compilé contre `uname -r` réel
reboot
```
Avantage : compilation contre le vrai kernel en cours, aucun pari.
Inconvénient : **transitoire** — à refaire après chaque `upgrade`
(ou à migrer en voie A ensuite). Vérif : `nvidia-smi`.

**Secure Boot dans les 2 voies :** kmods akmod/DKMS non signés par la
clé Fedora ⇒ soit Secure Boot OFF, soit enrôlement MOK (`mokutil
--import`), sinon écran noir au boot.

## 8. Diagnostiquer un boot raté

```
journalctl -b -1 -p err | tail -20  # erreurs du boot PRÉCÉDENT
journalctl -b -1 | grep -i -E "fail|nvidia|drm|gdm" | tail -30
systemctl --failed                   # services en échec sur le boot courant
```

Méthode : 1) lire l'erreur exacte, 2) UNE hypothèse, 3) UN changement,
4) reboot, 5) vérifier. Jamais 3 changements d'un coup — sinon on ne
sait plus ce qui a réparé (ou cassé).

## 9. Anti-sèches perso projet

- Build image : `./build.sh` (VM, sans Nvidia)
- ISO interactive : `./build.sh` → `./output/*.iso` (tester en VM d'abord)
- Driver host : `sudo ./install-nvidia-host.sh` (jamais en VM)
- Test VM : voir `Test bootc.txt` (commandes de contrôle groupées)
- Kernel + réglages CachyOS : **intouchables** (verrouillé)
- WiFi MT7927 : toujours dans l'image (indispensable host)

## 10. Règle d'or (à coller au mur)

> VM d'abord, host ensuite.
> 1 changement = 1 reboot = 1 test.
> `bootc status` avant et après. Rollback = parachute, ne jamais le brûler.
