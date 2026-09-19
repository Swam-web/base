#!/usr/bin/env bash
# build-all.sh — build d'une saveur bootc + ISO Anaconda interactive
#
# Usage :
#   ./build-all.sh <saveur> [tag-image]
# Exemples :
#   ./build-all.sh base
#   ./build-all.sh nvidia
#   ./build-all.sh nvidia localhost/mon-bootc:nvidia-rc
#
# Saveurs : base | nvidia | rocm | printer | full
#
# Ce que fait le script :
#   1. Build de l'image bootc locale avec les build-args de la saveur
#   2. Génération ISO Anaconda INTERACTIVE (kickstart vide → choix du disque)
#
# Sécurité :
#   - Aucun bootc install / dd / écriture sur /dev
#   - ISO interactive grâce à config.toml (NE JAMAIS remplir le kickstart)
set -euo pipefail

# --- Config ---
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"

# Ce script vit dans build/ — les chemins sont relatifs à la racine du projet.
cd "$(cd "$(dirname "$0")" && pwd)/.."

CONTAINERFILE="./Containerfile"
CONFIG="./build/config.toml"
OUTPUT_DIR="./build/output"

# --- Arguments ---
if [[ $# -ge 1 ]]; then
  # Mode direct : saveur passée en argument
  FLAVOR="$1"
  IMAGE="${2:-localhost/mon-bootc:${FLAVOR}}"
else
  # Mode interactif : menu de choix
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                 BUILD-ALL — CHOIX DE LA SAVEUR               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Saveurs disponibles :"
  echo "    1) base     — kernel, MT7927, GNOME, codecs, outils"
  echo "    2) nvidia   — + driver Nvidia baké dans l'image"
  echo "    3) rocm     — + userspace AMD"
  echo "    4) printer  — + hplip/gui"
  echo "    5) full     — nvidia + rocm + printer"
  echo ""
  read -rp "  Choix (1-5) : " CHOICE

  case "$CHOICE" in
    1) FLAVOR="base" ;;
    2) FLAVOR="nvidia" ;;
    3) FLAVOR="rocm" ;;
    4) FLAVOR="printer" ;;
    5) FLAVOR="full" ;;
    *)
      echo "ERREUR : choix '$CHOICE' invalide."
      exit 1
      ;;
  esac

  read -rp "  Tag image [localhost/mon-bootc:${FLAVOR}] : " TAG
  IMAGE="${TAG:-localhost/mon-bootc:${FLAVOR}}"
fi

case "$FLAVOR" in
  base|nvidia|rocm|printer|full) ;;
  *)
    echo "ERREUR : saveur inconnue '$FLAVOR'."
    echo "Saveurs valides : base | nvidia | rocm | printer | full"
    exit 1
    ;;
esac

# --- Vérifs ---
if [[ ! -f "$CONTAINERFILE" ]]; then
  echo "ERREUR : $CONTAINERFILE introuvable à la racine du projet."
  echo "Lance ce script depuis build/ : cd build && ./build-all.sh"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERREUR : $CONFIG introuvable (build/config.toml)."
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "ERREUR : podman non installé."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# S'assurer que le tag demandé existe bien dans le stockage local.
# Sans cela, bootc-image-builder peut chercher base:latest sur Docker Hub.
sudo podman image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo "ERREUR : image introuvable dans le stockage local : $IMAGE"
  echo "Vérifiez que podman a construit l'image avec le tag exact."
  exit 1
}

# --- build-args selon la saveur ---
WITH_NVIDIA=0; WITH_ROCM=0; WITH_PRINTER=0
case "$FLAVOR" in
  base)    ;;
  nvidia)  WITH_NVIDIA=1 ;;
  rocm)    WITH_ROCM=1 ;;
  printer) WITH_PRINTER=1 ;;
  full)    WITH_NVIDIA=1; WITH_ROCM=1; WITH_PRINTER=1 ;;
esac

# ==============================================================================
# 1. BUILD DE L'IMAGE BOOTC
# ==============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  BUILD-ALL — IMAGE BOOTC                    ║"
echo "║                  Saveur : $FLAVOR                          ║"
echo "║                  Image  : $IMAGE                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "==> [1/2] podman build (NVIDIA=$WITH_NVIDIA ROCM=$WITH_ROCM PRINTER=$WITH_PRINTER)..."
echo ""

sudo podman build --pull=newer \
  --build-arg "WITH_NVIDIA=$WITH_NVIDIA" \
  --build-arg "WITH_ROCM=$WITH_ROCM" \
  --build-arg "WITH_PRINTER=$WITH_PRINTER" \
  -t "$IMAGE" -f "$CONTAINERFILE" .

echo ""
echo "==> [1/2] Image $FLAVOR construite : $IMAGE"
echo ""

# ==============================================================================
# 2. GÉNÉRATION ISO ANACONDA INTERACTIVE
# ==============================================================================
echo ""
echo "==> [2/2] bootc-image-builder --type anaconda-iso (INTERACTIF)..."
echo ""
echo "    ISO à générer dans $OUTPUT_DIR/"
echo "    Anaconda demandera : langue, clavier, DISQUE, user."
echo ""

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
  "containers-storage:$IMAGE"

echo ""
echo "==> [2/2] ISO $FLAVOR générée dans $OUTPUT_DIR/"
echo ""

# ==============================================================================
# RÉSUMÉ
# ==============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                     BUILD-ALL TERMINÉ                       ║"
echo "║                     Saveur : $FLAVOR                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Image construite :"
echo "    • $IMAGE"
echo ""
echo "  ISO générée :"
echo "    • $OUTPUT_DIR/*.iso"
echo ""
echo "  Prochaines étapes :"
echo "    1. Tester l'ISO en VM (snapshot !)"
echo "    2. Si OK → bootc switch --transport containers-storage $IMAGE"
echo "    3. Vérifier : bootc status"
echo ""
echo "⚠️  Rappel : testez TOUJOURS en VM avant tout boot sur hardware."
echo "⚠️  L'ISO est INTERACTIVE : elle demande langue, clavier, DISQUE, user."
echo "   Ne JAMAIS automatiser (clearpart/autopart/kickstart rempli) avec"
echo "   plusieurs disques : risque d'effacement du mauvais disque."
echo ""
