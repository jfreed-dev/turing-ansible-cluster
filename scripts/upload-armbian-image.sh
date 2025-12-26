#!/bin/bash
# Upload Armbian images to Google Drive using rclone
#
# Usage: ./scripts/upload-armbian-image.sh <image-file> [destination-folder]
#
# Prerequisites:
#   - rclone installed and configured with a Google Drive remote
#   - Run 'rclone config' to set up a remote named 'gdrive' (or set RCLONE_REMOTE)
#
# Features:
#   - Compresses uncompressed .img files with xz
#   - Generates SHA256 checksums
#   - Uploads to organized folder structure
#   - Outputs shareable download link

set -e

# Configuration - Override via environment variables
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
GDRIVE_BASE_PATH="${GDRIVE_BASE_PATH:-armbian-builds/turing-rk1}"
COMPRESS_LEVEL="${COMPRESS_LEVEL:-6}"
CHUNK_SIZE="${CHUNK_SIZE:-256M}"
GENERATE_CHECKSUM="${GENERATE_CHECKSUM:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

usage() {
    cat << EOF
Usage: $0 <image-file> [destination-folder]

Upload Armbian images to Google Drive using rclone.

Arguments:
  image-file          Path to Armbian image (.img, .img.xz, .img.gz)
  destination-folder  Optional: subfolder in gdrive (default: based on date)

Environment variables:
  RCLONE_REMOTE       rclone remote name (default: gdrive)
  GDRIVE_BASE_PATH    Base path in Google Drive (default: armbian-builds/turing-rk1)
  COMPRESS_LEVEL      xz compression level 1-9 (default: 6)
  CHUNK_SIZE          Upload chunk size (default: 256M)
  GENERATE_CHECKSUM   Generate SHA256 checksum (default: true)

Examples:
  $0 Armbian_24.11_Turing-rk1.img
  $0 Armbian_24.11_Turing-rk1.img.xz stable
  RCLONE_REMOTE=mydrive $0 image.img nightly

Setup:
  1. Install rclone: sudo apt install rclone
  2. Configure Google Drive: rclone config
     - Choose 'n' for new remote
     - Name it 'gdrive' (or set RCLONE_REMOTE)
     - Choose 'drive' for Google Drive
     - Follow OAuth prompts

EOF
    exit 1
}

check_dependencies() {
    if ! command -v rclone &> /dev/null; then
        log_error "rclone is not installed"
        echo "Install with: sudo apt install rclone"
        echo "Then configure: rclone config"
        exit 1
    fi

    # Verify remote exists
    if ! rclone listremotes | grep -q "^${RCLONE_REMOTE}:$"; then
        log_error "rclone remote '${RCLONE_REMOTE}' not found"
        echo "Available remotes:"
        rclone listremotes
        echo ""
        echo "Create one with: rclone config"
        exit 1
    fi
}

compress_image() {
    local input="$1"
    local output="${input}.xz"

    if [[ -f "$output" ]]; then
        log_warn "Compressed file already exists: $output"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "$output"
            return
        fi
    fi

    log_info "Compressing image with xz (level $COMPRESS_LEVEL)..."
    log_info "This may take several minutes for large images"

    xz -k -${COMPRESS_LEVEL} -v "$input"

    log_info "Compression complete: $output"
    echo "$output"
}

generate_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"

    log_info "Generating SHA256 checksum..."
    sha256sum "$file" | tee "$checksum_file"
    echo "$checksum_file"
}

upload_file() {
    local file="$1"
    local dest_path="$2"

    log_info "Uploading: $(basename "$file")"
    log_info "Destination: ${RCLONE_REMOTE}:${dest_path}"

    rclone copy "$file" "${RCLONE_REMOTE}:${dest_path}" \
        --drive-chunk-size "$CHUNK_SIZE" \
        --progress \
        --stats-one-line \
        -v

    log_info "Upload complete!"
}

get_share_link() {
    local remote_path="$1"

    # Get the link (this sets the file to "anyone with link can view")
    local link
    link=$(rclone link "${RCLONE_REMOTE}:${remote_path}" 2>/dev/null || true)

    if [[ -n "$link" ]]; then
        echo "$link"
    fi
}

# Main script
if [[ $# -lt 1 ]]; then
    usage
fi

IMAGE_FILE="$1"
DEST_FOLDER="${2:-$(date +%Y-%m-%d)}"

if [[ ! -f "$IMAGE_FILE" ]]; then
    log_error "Image file not found: $IMAGE_FILE"
    exit 1
fi

check_dependencies

echo "=== Armbian Image Upload ==="
echo "Image: $IMAGE_FILE"
echo "Remote: ${RCLONE_REMOTE}:${GDRIVE_BASE_PATH}/${DEST_FOLDER}"
echo ""

# Determine if compression is needed
UPLOAD_FILE="$IMAGE_FILE"
case "$IMAGE_FILE" in
    *.img)
        log_info "Uncompressed image detected"
        read -p "Compress with xz before upload? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            UPLOAD_FILE=$(compress_image "$IMAGE_FILE")
        fi
        ;;
    *.img.xz|*.img.gz|*.img.zst)
        log_info "Compressed image detected, uploading as-is"
        ;;
    *)
        log_warn "Unknown file extension, uploading as-is"
        ;;
esac

# Generate checksum
CHECKSUM_FILE=""
if [[ "$GENERATE_CHECKSUM" == "true" ]]; then
    CHECKSUM_FILE=$(generate_checksum "$UPLOAD_FILE")
fi

# Build destination path
DEST_PATH="${GDRIVE_BASE_PATH}/${DEST_FOLDER}"

# Upload the image
upload_file "$UPLOAD_FILE" "$DEST_PATH"

# Upload checksum if generated
if [[ -n "$CHECKSUM_FILE" ]] && [[ -f "$CHECKSUM_FILE" ]]; then
    upload_file "$CHECKSUM_FILE" "$DEST_PATH"
fi

# Get shareable link
REMOTE_FILE="${DEST_PATH}/$(basename "$UPLOAD_FILE")"
SHARE_LINK=$(get_share_link "$REMOTE_FILE")

echo ""
echo "=== Upload Summary ==="
echo "File: $(basename "$UPLOAD_FILE")"
echo "Size: $(du -h "$UPLOAD_FILE" | cut -f1)"
echo "Location: ${RCLONE_REMOTE}:${REMOTE_FILE}"

if [[ -n "$SHARE_LINK" ]]; then
    echo ""
    echo "=== Shareable Link ==="
    echo "$SHARE_LINK"
    echo ""
    echo "Download with gdown:"
    echo "  pip install gdown"
    echo "  gdown --fuzzy '$SHARE_LINK'"
fi

echo ""
echo "=== List uploaded files ==="
rclone ls "${RCLONE_REMOTE}:${DEST_PATH}" 2>/dev/null || true
