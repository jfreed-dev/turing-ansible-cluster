#!/bin/bash
# Download Armbian images from Google Drive
#
# Usage: ./scripts/download-armbian-image.sh <url-or-file-id> [output-filename]
#
# Supports multiple download methods:
#   - gdown (recommended for large files)
#   - rclone (if configured)
#   - wget/curl (fallback)
#
# Features:
#   - Automatic checksum verification
#   - Handles Google Drive virus scan warnings
#   - Supports share links and direct file IDs

set -e

# Configuration
VERIFY_CHECKSUM="${VERIFY_CHECKSUM:-true}"
DECOMPRESS="${DECOMPRESS:-false}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-.}"

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
Usage: download-armbian-image.sh <url-or-file-id> [output-filename]

Download Armbian images from Google Drive with checksum verification.

Arguments:
  url-or-file-id    Google Drive share URL or file ID
  output-filename   Optional: output filename (auto-detected if omitted)

Environment variables:
  VERIFY_CHECKSUM   Verify SHA256 after download (default: true)
  DECOMPRESS        Decompress .xz/.gz files after download (default: false)
  DOWNLOAD_DIR      Directory to save files (default: current directory)

Supported URL formats:
  https://drive.google.com/file/d/FILE_ID/view?usp=sharing
  https://drive.google.com/open?id=FILE_ID
  https://drive.google.com/uc?id=FILE_ID
  FILE_ID (just the ID string)

Examples:
  # Download using share link
  ./download-armbian-image.sh 'https://drive.google.com/file/d/1abc.../view?usp=sharing'

  # Download using file ID
  ./download-armbian-image.sh 1abcDEF123xyz

  # Download and decompress
  DECOMPRESS=true ./download-armbian-image.sh 1abcDEF123xyz

  # Download to specific directory
  DOWNLOAD_DIR=/tmp ./download-armbian-image.sh 1abcDEF123xyz

Download methods (in order of preference):
  1. gdown  - Best for large files, handles virus scan warnings
  2. rclone - If you have Google Drive configured
  3. curl   - Fallback, may fail for files >100MB

Install gdown (recommended):
  pip install gdown

EOF
    exit 1
}

# Extract file ID from various Google Drive URL formats
extract_file_id() {
    local input="$1"
    local file_id=""

    # Already a file ID (no slashes or special chars)
    if [[ "$input" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#input} -gt 20 ]]; then
        echo "$input"
        return
    fi

    # Format: /file/d/FILE_ID/
    if [[ "$input" =~ /file/d/([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # Format: ?id=FILE_ID or &id=FILE_ID
    if [[ "$input" =~ [?\&]id=([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # Format: /folders/FOLDER_ID
    if [[ "$input" =~ /folders/([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # Could not extract
    echo ""
}

# Check which download tools are available
detect_download_method() {
    if command -v gdown &> /dev/null; then
        echo "gdown"
    elif command -v rclone &> /dev/null && rclone listremotes 2>/dev/null | grep -q ":"; then
        echo "rclone"
    elif command -v curl &> /dev/null; then
        echo "curl"
    elif command -v wget &> /dev/null; then
        echo "wget"
    else
        echo "none"
    fi
}

# Download using gdown (recommended)
download_with_gdown() {
    local file_id="$1"
    local output="$2"

    log_step "Downloading with gdown..."

    local args=("--fuzzy" "$file_id")

    if [[ -n "$output" ]]; then
        args+=("-O" "$output")
    fi

    gdown "${args[@]}"
}

# Download using rclone backend
download_with_rclone() {
    local file_id="$1"
    local output="$2"
    local remote

    # Find first available Google Drive remote
    remote=$(rclone listremotes | grep -E "^[^:]+:$" | head -1 | tr -d ':')

    if [[ -z "$remote" ]]; then
        log_error "No rclone remote found"
        return 1
    fi

    log_step "Downloading with rclone (remote: $remote)..."

    if [[ -n "$output" ]]; then
        rclone backend copyid "$remote": "$file_id" "$output" --progress
    else
        rclone backend copyid "$remote": "$file_id" . --progress
    fi
}

# Download using curl (fallback, limited to ~100MB)
download_with_curl() {
    local file_id="$1"
    local output="$2"

    log_step "Downloading with curl..."
    log_warn "curl may fail for files >100MB due to virus scan"

    local url="https://drive.usercontent.google.com/download?export=download&id=${file_id}&confirm=t"

    if [[ -n "$output" ]]; then
        curl -L -o "$output" "$url" --progress-bar
    else
        # Try to get filename from headers
        curl -L -O -J "$url" --progress-bar
    fi
}

# Download using wget (fallback)
download_with_wget() {
    local file_id="$1"
    local output="$2"

    log_step "Downloading with wget..."
    log_warn "wget may fail for files >100MB due to virus scan"

    local url="https://drive.usercontent.google.com/download?export=download&id=${file_id}&confirm=t"

    if [[ -n "$output" ]]; then
        wget -O "$output" "$url" --show-progress
    else
        wget --content-disposition "$url" --show-progress
    fi
}

# Verify SHA256 checksum
verify_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"

    # Try to download checksum file if it exists
    if [[ ! -f "$checksum_file" ]]; then
        log_info "Checksum file not found locally, skipping verification"
        return 0
    fi

    log_step "Verifying SHA256 checksum..."

    if sha256sum -c "$checksum_file"; then
        log_info "Checksum verified successfully!"
        return 0
    else
        log_error "Checksum verification FAILED!"
        return 1
    fi
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

# Main script
if [[ $# -lt 1 ]]; then
    usage
fi

INPUT="$1"
OUTPUT_FILE="${2:-}"

# Extract file ID
FILE_ID=$(extract_file_id "$INPUT")

if [[ -z "$FILE_ID" ]]; then
    log_error "Could not extract file ID from: $INPUT"
    echo ""
    echo "Expected formats:"
    echo "  https://drive.google.com/file/d/FILE_ID/view?usp=sharing"
    echo "  https://drive.google.com/open?id=FILE_ID"
    echo "  FILE_ID (just the ID)"
    exit 1
fi

log_info "File ID: $FILE_ID"

# Change to download directory
if [[ "$DOWNLOAD_DIR" != "." ]]; then
    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR"
    log_info "Download directory: $DOWNLOAD_DIR"
fi

# Detect best download method
METHOD=$(detect_download_method)
log_info "Download method: $METHOD"

echo ""
echo "=== Downloading Armbian Image ==="
echo ""

# Download the file
case "$METHOD" in
    gdown)
        download_with_gdown "$FILE_ID" "$OUTPUT_FILE"
        ;;
    rclone)
        download_with_rclone "$FILE_ID" "$OUTPUT_FILE"
        ;;
    curl)
        download_with_curl "$FILE_ID" "$OUTPUT_FILE"
        ;;
    wget)
        download_with_wget "$FILE_ID" "$OUTPUT_FILE"
        ;;
    none)
        log_error "No download tool available!"
        echo ""
        echo "Install one of the following:"
        echo "  pip install gdown     (recommended)"
        echo "  sudo apt install rclone"
        echo "  sudo apt install curl"
        exit 1
        ;;
esac

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

    # Verify checksum if requested
    if [[ "$VERIFY_CHECKSUM" == "true" ]]; then
        verify_checksum "$DOWNLOADED_FILE" || true
    fi

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
