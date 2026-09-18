#!/usr/bin/env bash
# setup-second-disk.sh — monte le 2e NVMe en /mnt/data polyvalent, SANS formater.
# Usage sur machine installée (pas au build) : sudo ./setup-second-disk.sh
# Sécu : aucun mkfs/format ici. Si le disque est vide sans filesystem, le script
# refuse et affiche la marche à suivre manuelle avec double confirmation.
set -euo pipefail

echo "=== Disques détectés ==="
lsblk -f
echo ""

read -rp "Partition à monter pour /mnt/data (ex: /dev/nvme1n1p1) : " PART
[[ -b "$PART" ]] || { echo "ERREUR : $PART n'est pas un périphérique bloc."; exit 1; }

FSTYPE=$(blkid -o value -s TYPE "$PART" || true)
UUID=$(blkid -o value -s UUID "$PART" || true)
if [[ -z "$FSTYPE" || -z "$UUID" ]]; then
  echo "REFUS : $PART n'a pas de filesystem détecté (vide ou inconnu)."
  echo "Ne formate que si c'est volontaire, en vérifiant 2 fois avec lsblk -f,"
  echo "exemple manuel : mkfs.btrfs -L DATA $PART  (EFFACE TOUT sur $PART)"
  exit 1
fi
echo "Détecté : $PART fstype=$FSTYPE uuid=$UUID"

read -rp "Monter $PART ($FSTYPE) en /mnt/data ? [o/N] : " OK
[[ "$OK" == "o" || "$OK" == "O" ]] || { echo "Annulé."; exit 0; }

mkdir -p /mnt/data
if grep -q " /mnt/data " /etc/fstab; then
  echo "/mnt/data déjà dans /etc/fstab, on garde l'entrée existante."
else
  if [[ "$FSTYPE" == "btrfs" ]]; then
    echo "UUID=$UUID /mnt/data btrfs noatime,compress=zstd:1,space_cache=v2 0 0" >> /etc/fstab
  else
    echo "UUID=$UUID /mnt/data $FSTYPE noatime 0 0" >> /etc/fstab
  fi
  echo "Entrée fstab ajoutée."
fi

mount /mnt/data
mkdir -p /mnt/data/iso /mnt/data/dossiers /mnt/data/fichiers /mnt/data/jeux
echo ""
echo "OK : /mnt/data monté ($FSTYPE). Arborescence polyvalente prête :"
ls -l /mnt/data
echo "Pointe Steam vers /mnt/data/jeux si tu veux, ISO dans /mnt/data/iso."
