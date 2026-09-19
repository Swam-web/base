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

## Structure

```
.
├── Containerfile              # recette image (20 étapes, 9 familles A–I)
├── build/
│   ├── build-all.sh           # build image + ISO anaconda-iso interactive (1 saveur)
│   ├── config.toml            # kickstart vide → Anaconda interactif
│   ├── FLAVOR                 # saveur par défaut (base|nvidia|rocm|printer|full)
│   └── output/                # ISO générée + manifest
├── host-scripts/              # scripts post-install sur machine bootc
│   ├── install-nvidia-host.sh # pilote Nvidia RPMFusion (akmod, 1er boot)
│   ├── install-rocm-host.sh   # ROCm userspace AMD (1er boot, optionnel)
│   ├── install-hplip-host.sh  # pilotes HP (1er boot, optionnel)
│   ├── install-flatpaks.sh    # flatpaks utiles + gaming
│   ├── setup-second-disk.sh   # monte 2e NVMe en /mnt/data par UUID
│   └── update-gui.py          # GUI GTK4 mises à jour bootc + flatpak
└── docs/                      # docs, tutoriels, mémo
    ├── TUTO.md                # tutoriel FR complet
    ├── TUTO.en.md             # tutoriel EN complet
    ├── memo-bootc.html        # mémo commandes quotidiennes (à imprimer)
    ├── TUTO.pdf               # tutoriel FR complet (PDF)
    └── TUTO.en.pdf            # tutoriel EN complet (PDF)
    └── test-vm.md             # procédure de test en VM
```

## Build et 1er boot

```
cd build && ./build-all.sh
```

Saveurs : `base` · `nvidia` · `rocm` · `printer` · `full`.

Tester l'ISO en VM snapshotée avant tout bare metal. Au 1er boot :
`snapper` configs, `sudo setup-second-disk.sh`, `sudo install-flatpaks.sh`,
`p10k configure`, profil Performance sur secteur.
