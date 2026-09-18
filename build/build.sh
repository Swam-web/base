#!/usr/bin/env bash
# build.sh — build image bootc + ISO Anaconda INTERACTIVE (façon Fedora classique)
#
# Usage :
#   ./build.sh [nom-image:tag] [saveur]
#   Saveurs : base (défaut), nvidia, rocm, printer, full
# Exemples :
#   ./build.sh localhost/mon-bootc:latest
#   ./build.sh localhost/mon-bootc:nvidia nvidia
#   WITH_NVIDIA=1 WITH_PRINTER=1 ./build.sh localhost/mon-bootc:full full
#
# Ce que fait le script :
#   1. podman build à partir de ./Containerfile -> image locale
#   2. bootc-image-builder --type anaconda-iso -> ./output/*.iso
#
# Sécurité :
#   - Aucun `bootc install to-disk`, aucun `dd`, aucune écriture sur /dev.
#   - L'ISO produite est INTERACTIVE grâce à config.toml (kickstart vide).
#   - Testez TOUJOURS l'ISO en VM (qemu/libvirt) avant tout boot sur machine réelle.
set -euo pipefail

# --- Config ---
IMAGE="${1:-localhost/mon-bootc:latest}"
# Saveur : 2e arg, sinon fichier FLAVOR (une ligne : base|nvidia|rocm|printer|full),
# sinon base.
FLAVOR="${2:-$(cat "$(dirname "$0")/FLAVOR" 2>/dev/null || echo base)}"
CONTAINERFILE="./Containerfile"
CONFIG="./build/config.toml"
OUTPUT_DIR="./build/output"
# Ce script vit dans build/ — les chemins sont relatifs à la racine du projet.
cd "$(dirname "$0")/.."
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"

# Saveur -> build-args (base = tout à 0). Les exports manuels
# (WITH_NVIDIA=1 ./build.sh ...) ont priorité sur la saveur.
: "${WITH_NVIDIA:=0}"; : "${WITH_ROCM:=0}"; : "${WITH_PRINTER:=0}"
case "$FLAVOR" in
  base)    ;;
  nvidia)  WITH_NVIDIA=1 ;;
  rocm)    WITH_ROCM=1 ;;
  printer) WITH_PRINTER=1 ;;
  full)    WITH_NVIDIA=1; WITH_ROCM=1; WITH_PRINTER=1 ;;
  *) echo "Saveur inconnue : $FLAVOR (base|nvidia|rocm|printer|full)"; exit 1 ;;
esac

echo "==> Image cible : $IMAGE (saveur $FLAVOR)"
echo "==> Containerfile : $CONTAINERFILE"
echo "==> Config BIB : $CONFIG"

# --- Vérifs ---
if [[ ! -f "$CONTAINERFILE" ]]; then
  echo "ERREUR : $CONTAINERFILE introuvable."
  echo "On le fera ensemble à l'étape suivante. Le build ISO attendra ce fichier."
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERREUR : $CONFIG introuvable. Il doit contenir le kickstart vide interactif."
  exit 1
fi

command -v podman >/dev/null 2>&1 || { echo "ERREUR : podman non installé."; exit 1; }

mkdir -p "$OUTPUT_DIR"

# --- 1. Build de l'image bootc ---
echo "==> [1/2] podman build (NVIDIA=$WITH_NVIDIA ROCM=$WITH_ROCM PRINTER=$WITH_PRINTER)..."
sudo podman build --pull=newer \
  --build-arg "WITH_NVIDIA=${WITH_NVIDIA:-0}" \
  --build-arg "WITH_ROCM=${WITH_ROCM:-0}" \
  --build-arg "WITH_PRINTER=${WITH_PRINTER:-0}" \
  -t "$IMAGE" -f "$CONTAINERFILE" .

# --- 2. Build de l'ISO Anaconda interactive (optionnel) ---
# SKIP_ISO=1 désactive la génération ISO (utile sur CI / runners compatibles).
if [[ "${SKIP_ISO:-0}" != "1" ]]; then
  echo "==> [2/2] bootc-image-builder --type anaconda-iso (interactif)..."
  sudo podman run --rm -i \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "$OUTPUT_DIR:/output" \
    -v "$CONFIG:/config.toml:ro" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "$BIB_IMAGE" \
    --type anaconda-iso \
    --rootfs btrfs \
    --config /config.toml \
    "$IMAGE"

  echo ""
  echo "==> [2/2] ISO générée dans $OUTPUT_DIR/"
else
  echo "==> [2/2] Génération ISO ignorée (SKIP_ISO=1)."
  echo "    Pour générer l'ISO Anaconda interactive en local :"
  echo "    cd build && ./build-all.sh"
fi

echo ""
echo "OK : image locale construite pour $IMAGE (saveur $FLAVOR)."
echo ""
echo "L'ISO est INTERACTIVE grâce à config.toml : elle demande langue, clavier,"
echo "disque et création user. Ne JAMAIS automatiser (clearpart/autopart/kickstart rempli)"
echo "avec plusieurs disques : risque d'effacement du mauvais disque."
echo ""
echo "Prochain boot : en VM d'abord. Anaconda doit vous demander langue, clavier, disque, user."
echo "Si Anaconda n'a rien demandé et a tout effacé, c'est que le kickstart n'était pas vide -> ne bootez pas sur hardware."
