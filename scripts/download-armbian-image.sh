#!/bin/bash
# Download Armbian images from Cloudflare R2
#
# Usage: ./scripts/download-armbian-image.sh --latest
#        ./scripts/download-armbian-image.sh <url> [output-filename]
#
# Features:
#   - Automatic checksum verification
#   - --latest flag to download from images.json metadata
#   - Optional auto-decompression

set -e

# Configuration
VERIFY_CHECKSUM="${VERIFY_CHECKSUM:-true}"
DECOMPRESS="${DECOMPRESS:-false}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

usage() {
    cat << 'EOF'
Usage: download-armbian-image.sh [--latest | <url>] [output-filename]

Download Armbian images from Cloudflare R2.

Arguments:
  --latest          Download the latest image from images.json metadata
  url               Direct download URL
  output-filename   Optional: output filename (auto-detected if omitted)

Environment variables:
  VERIFY_CHECKSUM   Verify SHA256 after download (default: true)
  DECOMPRESS        Decompress .xz/.gz files after download (default: false)
  DOWNLOAD_DIR      Directory to save files (default: current directory)

Examples:
  # Download latest image (reads from images.json)
  ./download-armbian-image.sh --latest

  # Download and decompress
  DECOMPRESS=true ./download-armbian-image.sh --latest

  # Download to specific directory
  DOWNLOAD_DIR=/tmp ./download-armbian-image.sh --latest

  # Download from direct URL
  ./download-armbian-image.sh https://armbian-builds.techki.to/turing-rk1/26.02.0-trunk/Armbian.img.xz

EOF
    exit 1
}

# Decompress file
decompress_file() {
    local file="$1"

    case "$file" in
        *.xz)
            log_step "Decompressing with xz..."
            xz -d -k -v "$file"
            log_info "Decompressed: ${file%.xz}"
            ;;
        *.gz)
            log_step "Decompressing with gzip..."
            gzip -d -k -v "$file"
            log_info "Decompressed: ${file%.gz}"
            ;;
        *.zst)
            log_step "Decompressing with zstd..."
            zstd -d -k "$file"
            log_info "Decompressed: ${file%.zst}"
            ;;
        *)
            log_info "File does not need decompression"
            ;;
    esac
}

# Download from URL
download_url() {
    local url="$1"
    local output="$2"

    log_step "Downloading from URL..."

    if [[ -n "$output" ]]; then
        curl -L -o "$output" "$url" --progress-bar
    else
        curl -L -O -J "$url" --progress-bar
    fi
}

# Fetch latest image info from images.json
get_latest_image() {
    local images_json="${REPO_ROOT}/images.json"

    if [[ ! -f "$images_json" ]]; then
        log_error "images.json not found at: $images_json"
        echo "Run this script from the repository root or ensure images.json exists."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required for --latest. Install with: sudo apt install jq"
        exit 1
    fi

    local download_url=$(jq -r '.latest.download_url // ""' "$images_json")
    local filename=$(jq -r '.latest.filename // ""' "$images_json")
    local sha256=$(jq -r '.latest.sha256 // ""' "$images_json")
    local version=$(jq -r '.latest.armbian_version // ""' "$images_json")

    if [[ -z "$download_url" ]] || [[ "$download_url" == "null" ]]; then
        log_error "No download URL found in images.json"
        exit 1
    fi

    echo ""
    echo "=== Latest Armbian Image ==="
    echo "Version: $version"
    echo "Filename: $filename"
    echo "SHA256: $sha256"
    echo ""

    # Export for use in main script
    LATEST_URL="$download_url"
    LATEST_FILENAME="$filename"
    LATEST_SHA256="$sha256"
}

# Main script
if [[ $# -lt 1 ]]; then
    usage
fi

INPUT="$1"
OUTPUT_FILE="${2:-}"

# Handle --latest flag
if [[ "$INPUT" == "--latest" ]]; then
    get_latest_image

    # Change to download directory
    if [[ "$DOWNLOAD_DIR" != "." ]]; then
        mkdir -p "$DOWNLOAD_DIR"
        cd "$DOWNLOAD_DIR"
        log_info "Download directory: $DOWNLOAD_DIR"
    fi

    echo "=== Downloading Armbian Image ==="
    echo ""

    download_url "$LATEST_URL" "$LATEST_FILENAME"

    DOWNLOADED_FILE="$LATEST_FILENAME"

    echo ""
    echo "=== Download Complete ==="
    echo "File: $DOWNLOADED_FILE"
    echo "Size: $(du -h "$DOWNLOADED_FILE" | cut -f1)"

    # Verify checksum
    if [[ "$VERIFY_CHECKSUM" == "true" ]] && [[ -n "$LATEST_SHA256" ]]; then
        log_step "Verifying SHA256 checksum..."
        echo "$LATEST_SHA256  $DOWNLOADED_FILE" | sha256sum -c
    fi

    # Decompress if requested
    if [[ "$DECOMPRESS" == "true" ]]; then
        decompress_file "$DOWNLOADED_FILE"
    fi

    echo ""
    echo "=== Next Steps ==="
    echo "1. Decompress (if needed):"
    echo "   xz -d ${DOWNLOADED_FILE}"
    echo ""
    echo "2. Prepare the image:"
    echo "   ./scripts/prepare-armbian-image.sh ${DOWNLOADED_FILE%.xz} 1"
    echo ""
    echo "3. Flash to node:"
    echo "   tpi flash --node 1 --image-path ${DOWNLOADED_FILE%.xz}"

    exit 0
fi

# Direct URL download
if [[ "$INPUT" == http* ]]; then
    # Change to download directory
    if [[ "$DOWNLOAD_DIR" != "." ]]; then
        mkdir -p "$DOWNLOAD_DIR"
        cd "$DOWNLOAD_DIR"
        log_info "Download directory: $DOWNLOAD_DIR"
    fi

    echo "=== Downloading Armbian Image ==="
    echo ""

    download_url "$INPUT" "$OUTPUT_FILE"

    # Find the downloaded file
    if [[ -n "$OUTPUT_FILE" ]]; then
        DOWNLOADED_FILE="$OUTPUT_FILE"
    else
        # Find most recently modified file
        DOWNLOADED_FILE=$(ls -t *.img* 2>/dev/null | head -1 || true)
    fi

    if [[ -z "$DOWNLOADED_FILE" ]] || [[ ! -f "$DOWNLOADED_FILE" ]]; then
        log_warn "Could not locate downloaded file"
    else
        echo ""
        echo "=== Download Complete ==="
        echo "File: $DOWNLOADED_FILE"
        echo "Size: $(du -h "$DOWNLOADED_FILE" | cut -f1)"

        # Decompress if requested
        if [[ "$DECOMPRESS" == "true" ]]; then
            decompress_file "$DOWNLOADED_FILE"
        fi

        echo ""
        echo "=== Next Steps ==="
        echo "1. Prepare the image:"
        echo "   ./scripts/prepare-armbian-image.sh $DOWNLOADED_FILE 1"
        echo ""
        echo "2. Flash to node:"
        echo "   tpi flash --node 1 --image-path ${DOWNLOADED_FILE%.xz}"
    fi

    exit 0
fi

# Unknown input
log_error "Unknown input: $INPUT"
echo ""
echo "Use --latest to download the latest image, or provide a direct URL."
usage
