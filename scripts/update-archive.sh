#!/usr/bin/env bash
#
# update-archive.sh
#
# Downloads and updates the offline archive on disk1.
# All ZIM files go to /mnt/disk1/archive/kiwix/.
#
# This script is designed to be re-run — it checks for newer versions
# before downloading and only pulls what's changed.
#
# Usage:
#   sudo bash /tmp/update-archive.sh              # Download/update everything
#   sudo bash /tmp/update-archive.sh --list        # Show what would be downloaded (dry run)
#   sudo bash /tmp/update-archive.sh --parallel 3  # Download 3 files at once (default: 2)
#   sudo bash /tmp/update-archive.sh --sequential  # Download one at a time (shows progress inline)
#
# Monitor parallel downloads:
#   tail -f /mnt/disk1/archive/logs/download-*.log  # Watch all downloads
#   ls -lh /mnt/disk1/archive/kiwix/*.part           # Check file sizes growing
#
# Requires: wget, curl
# Run on the Raspberry Pi as root (files in /mnt/disk1 are owned by root).

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

ARCHIVE_DIR="/mnt/disk1/archive"
KIWIX_DIR="${ARCHIVE_DIR}/kiwix"
MANIFEST="${KIWIX_DIR}/manifest.txt"
LOG_DIR="${ARCHIVE_DIR}/logs"
# Primary mirror — download.kiwix.org often redirects to dead mirrors,
# so we use a known-good mirror directly. Change this if it stops working.
# Other mirrors: https://download.kiwix.org/mirrors.html
#   - https://ftp.nluug.nl/pub/kiwix/zim   (Netherlands)
#   - https://mirror.download.kiwix.org/zim (France, Kiwix self-mirror)
#   - https://ftpmirror.your.org/pub/kiwix/zim (US)
KIWIX_BASE_URL="https://ftp.fau.de/kiwix/zim"

MAX_PARALLEL="${MAX_PARALLEL:-4}"
DRY_RUN=false
SEQUENTIAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list|--dry-run)
      DRY_RUN=true
      shift
      ;;
    --parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --sequential)
      SEQUENTIAL=true
      MAX_PARALLEL=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--list] [--parallel N] [--sequential]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# ZIM catalog
#
# Each entry: "category|filename_pattern|description"
#
# The filename_pattern is a sed expression that matches the ZIM filename
# in the Kiwix directory listing. The script finds the latest version
# automatically by sorting matches.
#
# To add a new ZIM source, just add a line here.
# ---------------------------------------------------------------------------

ZIM_CATALOG=(
  # Wikimedia
  "wikipedia|wikipedia_en_all_maxi_|Wikipedia EN (full text + images)"
  "wikibooks|wikibooks_en_all_maxi_|Wikibooks EN (free textbooks)"
  "wikivoyage|wikivoyage_en_all_maxi_|Wikivoyage EN (travel guides)"

  # Stack Exchange
  "stack_exchange|stackoverflow.com_en_all_|Stack Overflow"
  "stack_exchange|askubuntu.com_en_all_|Ask Ubuntu"
  "stack_exchange|superuser.com_en_all_|Super User"
  "stack_exchange|unix.stackexchange.com_en_all_|Unix & Linux Stack Exchange"
  "stack_exchange|math.stackexchange.com_en_all_|Math Stack Exchange"

  # Reference
  "ifixit|ifixit_en_all_|iFixit repair guides"

  # Books
  "gutenberg|gutenberg_en_all_|Project Gutenberg (60,000+ free ebooks)"
)

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  if [[ "$DRY_RUN" == false ]]; then
    echo "$msg" >> "${LOG_DIR}/update-archive.log"
  fi
}

# Find the latest ZIM filename for a given category and pattern.
# Scrapes the Kiwix directory listing and returns the newest match.
find_latest_zim() {
  local category="$1"
  local pattern="$2"
  local url="${KIWIX_BASE_URL}/${category}/"

  curl -s "$url" \
    | sed -n "s/.*href=\"\(${pattern}[0-9-]*\.zim\)\".*/\1/p" \
    | sort -V \
    | tail -1
}

# Check if we already have this ZIM or a newer version.
# Returns 0 if download is needed, 1 if we're up to date.
needs_download() {
  local pattern="$1"
  local latest_file="$2"

  if [[ -f "${KIWIX_DIR}/${latest_file}" ]]; then
    return 1
  fi

  return 0
}

# Find any older versions of this ZIM pattern that exist locally.
find_local_versions() {
  local pattern="$1"
  find "${KIWIX_DIR}" -maxdepth 1 -name "${pattern}*.zim" -type f 2>/dev/null || true
}

# Download a single ZIM file with resume support.
# IMPORTANT: We download directly to the final filename (no -O flag) so that
# wget's --continue flag works correctly. Using -O with --continue causes
# wget to truncate the file on retry, destroying partial downloads.
# In sequential mode, progress goes to the console.
# In parallel mode, progress goes to a per-file log.
download_zim() {
  local category="$1"
  local filename="$2"
  local description="$3"
  local index="$4"
  local total="$5"
  local url="${KIWIX_BASE_URL}/${category}/${filename}"
  local dest="${KIWIX_DIR}/${filename}"
  local download_log="${LOG_DIR}/download-${filename}.log"

  if [[ "$SEQUENTIAL" == true ]]; then
    # Sequential: progress bar prints directly to the console
    echo ""
    echo "[$index/$total] ${description}"
    echo "  URL:  ${url}"
    echo "  DEST: ${dest}"
    echo ""

    # Download directly into KIWIX_DIR with the server's filename.
    # --continue resumes partial downloads correctly this way.
    (cd "${KIWIX_DIR}" && wget \
      --continue \
      --timeout=30 \
      --tries=20 \
      --waitretry=10 \
      --progress=bar:force:noscroll \
      "${url}" 2>&1)

  else
    # Parallel: progress goes to a per-file log
    echo "[$(date '+%H:%M:%S')] Started [$index/$total]: ${description}" | tee -a "${LOG_DIR}/update-archive.log"
    echo "  Log: tail -f ${download_log}"

    {
      echo "Downloading: ${description}"
      echo "URL:  ${url}"
      echo "Dest: ${dest}"
      echo "Started: $(date)"
      echo ""
      (cd "${KIWIX_DIR}" && wget \
        --continue \
        --timeout=30 \
        --tries=20 \
        --waitretry=10 \
        --progress=dot:mega \
        "${url}" 2>&1)
      echo ""
      echo "Finished: $(date)"
    } > "${download_log}" 2>&1
  fi

  # Update manifest
  echo "$(date '+%Y-%m-%d %H:%M:%S') | ${filename} | ${description}" >> "${MANIFEST}"

  echo "[$(date '+%H:%M:%S')] COMPLETE [$index/$total]: ${description} -> ${filename}"
}

# Show a summary of in-progress downloads (file sizes of .part files)
show_progress() {
  local part_files
  part_files=$(find "${KIWIX_DIR}" -name "*.part" -type f 2>/dev/null)
  if [[ -n "$part_files" ]]; then
    echo ""
    echo "--- Download progress ---"
    for f in $part_files; do
      local base
      base=$(basename "$f" .part)
      local size
      size=$(du -h "$f" 2>/dev/null | cut -f1)
      echo "  ${base}: ${size} downloaded"
    done
    echo "-------------------------"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  Offline Archive Update"
echo "  Target: ${KIWIX_DIR}"
echo "=========================================="
echo ""

# Create directories
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "${KIWIX_DIR}"
  mkdir -p "${LOG_DIR}"
  touch "${MANIFEST}"
fi

# Build download queue
declare -a DOWNLOAD_QUEUE_CAT=()
declare -a DOWNLOAD_QUEUE_FILE=()
declare -a DOWNLOAD_QUEUE_DESC=()
declare -a SKIP_LIST=()

echo "Checking for updates..."
echo ""

for entry in "${ZIM_CATALOG[@]}"; do
  IFS='|' read -r category pattern description <<< "$entry"

  latest=$(find_latest_zim "$category" "$pattern")

  if [[ -z "$latest" ]]; then
    echo "  WARNING: Could not find ZIM for pattern '${pattern}' in ${category}/"
    continue
  fi

  if needs_download "$pattern" "$latest"; then
    local_versions=$(find_local_versions "$pattern")
    if [[ -n "$local_versions" ]]; then
      echo "  UPDATE:  ${description}"
      echo "           ${latest} (replaces older version)"
      echo "           Old version(s) will be kept — remove manually when ready."
    else
      echo "  NEW:     ${description}"
      echo "           ${latest}"
    fi

    DOWNLOAD_QUEUE_CAT+=("$category")
    DOWNLOAD_QUEUE_FILE+=("$latest")
    DOWNLOAD_QUEUE_DESC+=("$description")
  else
    SKIP_LIST+=("${description} [${latest}]")
  fi
done

echo ""

if [[ ${#SKIP_LIST[@]} -gt 0 ]]; then
  echo "Already up to date:"
  for item in "${SKIP_LIST[@]}"; do
    echo "  OK:      ${item}"
  done
  echo ""
fi

if [[ ${#DOWNLOAD_QUEUE_FILE[@]} -eq 0 ]]; then
  echo "Everything is up to date. Nothing to download."
  exit 0
fi

TOTAL=${#DOWNLOAD_QUEUE_FILE[@]}

if [[ "$SEQUENTIAL" == true ]]; then
  echo "=========================================="
  echo "  ${TOTAL} file(s) to download (sequential)"
  echo "  Destination: ${KIWIX_DIR}"
  echo "=========================================="
else
  echo "=========================================="
  echo "  ${TOTAL} file(s) to download"
  echo "  Parallel downloads: ${MAX_PARALLEL}"
  echo "  Destination: ${KIWIX_DIR}"
  echo "=========================================="
  echo ""
  echo "  Monitor progress:"
  echo "    tail -f ${LOG_DIR}/download-*.log"
  echo "    ls -lh ${KIWIX_DIR}/*.part"
fi
echo ""

for i in "${!DOWNLOAD_QUEUE_FILE[@]}"; do
  echo "  $(( i + 1 )). ${DOWNLOAD_QUEUE_DESC[$i]}"
  echo "     ${DOWNLOAD_QUEUE_FILE[$i]}"
done
echo ""

# Dry run stops here
if [[ "$DRY_RUN" == true ]]; then
  echo "(Dry run — nothing was downloaded)"
  exit 0
fi

if [[ "$SEQUENTIAL" == true ]]; then
  # Sequential mode: download one at a time, progress to console
  for i in "${!DOWNLOAD_QUEUE_FILE[@]}"; do
    download_zim \
      "${DOWNLOAD_QUEUE_CAT[$i]}" \
      "${DOWNLOAD_QUEUE_FILE[$i]}" \
      "${DOWNLOAD_QUEUE_DESC[$i]}" \
      "$(( i + 1 ))" \
      "${TOTAL}"
  done
else
  # Parallel mode: downloads in background, progress to per-file logs
  log "Starting downloads (max ${MAX_PARALLEL} parallel)..."
  echo ""

  active_jobs=0
  for i in "${!DOWNLOAD_QUEUE_FILE[@]}"; do
    # Wait if we've hit the parallel limit
    while [[ $active_jobs -ge $MAX_PARALLEL ]]; do
      wait -n 2>/dev/null || true
      active_jobs=$(jobs -rp | wc -l)
    done

    # Launch download in background
    download_zim \
      "${DOWNLOAD_QUEUE_CAT[$i]}" \
      "${DOWNLOAD_QUEUE_FILE[$i]}" \
      "${DOWNLOAD_QUEUE_DESC[$i]}" \
      "$(( i + 1 ))" \
      "${TOTAL}" &

    active_jobs=$(jobs -rp | wc -l)
  done

  # Wait for all remaining downloads
  echo ""
  echo "All downloads launched. Waiting for completion..."
  echo "  Monitor: tail -f ${LOG_DIR}/download-*.log"
  echo "  Sizes:   watch ls -lh ${KIWIX_DIR}/*.part"
  echo ""
  wait
fi

echo ""
echo "=========================================="
echo "  All downloads complete!"
echo "  Files are in: ${KIWIX_DIR}"
echo "  Manifest:     ${MANIFEST}"
echo "  Log:          ${LOG_DIR}/update-archive.log"
echo "=========================================="
echo ""
echo "Kiwix will automatically detect the new ZIM files."
echo "Browse your archive at: http://archive.home.arpa"
echo ""
