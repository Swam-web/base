#!/usr/bin/env bash
# build-all.sh — build séquentiel des saveurs base + nvidia
#
# Usage :
#   ./build-all.sh [tag-base] [tag-nvidia]
# Exemples :
#   ./build-all.sh
#   ./build-all.sh localhost/mon-bootc:latest localhost/mon-bootc:nvidia
#   ./build-all.sh localhost/mon-bootc:rc localhost/mon-bootc:nvidia-rc
#
# Ce que fait le script :
#   1. Build de la saveur BASE (kernel, MT7927, GNOME, codecs)
#   2. Build de la saveur NVIDIA (+ driver Nvidia baké)
#   3. Build de la ISO Anaconda interactive pour chaque saveur
#
# Sécurité :
#   - Aucune écriture sur /dev, aucun dd
#   - Chaque build produit une ISO interactive (config.toml kickstart vide)
set -euo pipefail

# --- Config ---
TAG_BASE="${1:-localhost/mon-bootc:latest}"
TAG_NVIDIA="${2:-localhost/mon-bootc:nvidia}"
CONTAINERFILE="./Containerfile"
CONFIG="./build/config.toml"
FLAVOR_FILE="./build/FLAVOR"
OUTPUT_DIR="./build/output"
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"

# --- Vérifs ---
if [[ ! -f "$CONTAINERFILE" ]]; then
  echo "ERREUR : $CONTAINERFILE introuvable."
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERREUR : $CONFIG introuvable."
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "ERREUR : podman non installé."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ==============================================================================
# 1. Build BASE
# ==============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    [1/2] BUILD BASE                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "==> Image cible : $TAG_BASE"
echo ""

sudo podman build --pull=newer \
  --build-arg WITH_NVIDIA=0 \
  --build-arg WITH_ROCM=0 \
  --build-arg WITH_PRINTER=0 \
  -t "$TAG_BASE" -f "$CONTAINERFILE" .

echo ""
echo "==> [1/2] Image base construite : $TAG_BASE"
echo ""

# --- ISO Anaconda interactive (base) ---
echo ""
echo "==> [1/2] Génération ISO Anaconda interactive (base)..."
echo ""

sudo podman run --rm -it \
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
  "$TAG_BASE"

echo ""
echo "==> [1/2] ISO base générée dans $OUTPUT_DIR/"
echo ""

# ==============================================================================
# 2. Build NVIDIA
# ==============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   [2/2] BUILD NVIDIA                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "==> Image cible : $TAG_NVIDIA"
echo ""

sudo podman build --pull=newer \
  --build-arg WITH_NVIDIA=1 \
  --build-arg WITH_ROCM=0 \
  --build-arg WITH_PRINTER=0 \
  -t "$TAG_NVIDIA" -f "$CONTAINERFILE" .

echo ""
echo "==> [2/2] Image nvidia construite : $TAG_NVIDIA"
echo ""

# --- ISO Anaconda interactive (nvidia) ---
echo ""
echo "==> [2/2] Génération ISO Anaconda interactive (nvidia)..."
echo ""

sudo podman run --rm -it \
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
  "$TAG_NVIDIA"

echo ""
echo "==> [2/2] ISO nvidia générée dans $OUTPUT_DIR/"
echo ""

# ==============================================================================
# RÉSUMÉ
# ==============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                     BUILD-ALL TERMINÉ                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Images construites :"
echo "    • $TAG_BASE"
echo "    • $TAG_NVIDIA"
echo ""
echo "  ISOs générées :"
echo "    • $OUTPUT_DIR/*.iso"
echo ""
echo "  Prochaines étapes :"
echo "    1. Tester les ISOs en VM (snapshot !)"
echo "    2. Si OK → transfert + switch sur machine réelle"
echo "    3. Vérifier : nvidia-smi / bootc status"
echo ""
echo "  Commandes utiles :"
echo "    bootc switch --transport containers-storage $TAG_BASE"
echo "    bootc switch --transport containers-storage $TAG_NVIDIA"
echo "    bootc status"
echo ""
echo "⚠️  Rappel : testez TOUJOURS en VM avant tout boot sur hardware."
echo ""
