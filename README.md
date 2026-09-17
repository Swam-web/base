# Image bootc Fedora 44 — poste i9-14900K + RTX 4070

Fedora 44 bootc, kernel CachyOS 7.2.x, Nvidia 615 Negativo17, GNOME Workstation,
gaming, MT7927. Installateur Anaconda interactif façon Fedora officielle.

## Schéma des couches

```
quay.io/fedora/fedora-bootc:44
│
├─ A. NOYAU ──────────────── 1. kernel CachyOS 7.2.x + initramfs
│
├─ B. PILOTES ────────────── 2. Nvidia 615 Negativo17 (akmod)
│                            3. MT7927 DKMS v2.14-6 + firmware BT
│
├─ C. SYSTÈME ────────────── 4. bootc/ostree + snapper + outils
│
├─ D. MULTIMÉDIA ─────────── 5. codecs Negativo17 (+RPMFusion off)
│                            6. AppImage FUSE + Flatpak/Flathub
│
├─ E. ADDONS ─────────────── 7. cachyos-settings, scx, ananicy
│
├─ F. GAMING ─────────────── 8. steam/wine/lutris/mangohud
│                           12. scx_lavd, gamemode, kargs Nvidia
│
├─ G. BUREAU ─────────────── 9. tweaks/extensions
│                           10. GNOME Workstation + gdm
│                           14. XWayland, Tracker, extensions RPM
│
├─ H. OPTIMISATIONS ──────── 11. microcode, tuned, NVMe
│                           13. btrfs, oomd, WiFi, libvirt
│                           15. audio, réseau, pare-feu, updates
│                           16. portails, codecs BT, chrony
│                           17. IOMMU + initramfs finale
│
├─ I. OUTILS ─────────────── 18. distrobox, cups, vulkan, hplip
│                           19. zsh + plugins RPM
│                           20. oh-my-zsh + powerlevel10k
│
▼
localhost/mon-bootc:latest → bootc-image-builder → output/*.iso
```

## Fichiers

- `Containerfile` : la recette, 20 étapes en 9 familles A–I
- `build.sh` : build image puis ISO anaconda-iso interactive dans `./output/`
- `config.toml` : kickstart vide, Anaconda demande langue, clavier, disque, user
- `setup-second-disk.sh` : monte le 2e NVMe en `/mnt/data` par UUID, sans jamais formater
- `install-flatpaks.sh` : Bazaar, Extension Manager, Gearlever, Heroic, ProtonUp-Qt
- `memo-bootc.pdf` : mémo des commandes quotidiennes

## Build et 1er boot

```
./build.sh localhost/mon-bootc:latest 2>&1 | tee build.log
```

Tester l'ISO en VM snapshotée avant tout bare metal. Au 1er boot :
`snapper` configs, `sudo setup-second-disk.sh`, `sudo install-flatpaks.sh`,
`p10k configure`, profil Performance sur secteur.
