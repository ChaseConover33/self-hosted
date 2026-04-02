# Offline Archive

The archive lives on disk1 at `/mnt/disk1/archive/` and provides offline access to
reference knowledge, books, and other resources. Content is stored as Kiwix ZIM files
and served through a web UI at `https://archive.lab.chaseconover.com`.

## Architecture

```
/mnt/disk1/archive/
├── kiwix/              # ZIM files — served by the kiwix Docker container
│   ├── manifest.txt    # Log of downloaded files and dates
│   └── *.zim          # Downloaded ZIM archives
├── logs/               # Download logs
│   ├── update-archive.log
│   └── download-*.log  # Per-file download progress (parallel mode)
├── books/              # (future) Project Gutenberg rsync mirror
├── reference/          # (future) OpenStax textbooks, field manuals
├── medical/            # (future) WHO guides, first aid references
├── maps/               # (future) Protomaps PMTiles
├── historical/         # (future) Archive.org downloads
├── repos/              # (future) Git mirrors of critical projects
└── extracted/          # (future) Text extracted from ZIMs for AI indexing
```

ZIM files are the source of truth. They are compressed archives containing full
websites (HTML, images, metadata) in a single file. Kiwix Serve reads them
directly and provides a searchable web interface.

## Current ZIM Collections

| Collection | Source | Approx Size | Update Frequency |
|---|---|---|---|
| Wikipedia EN (text + images) | wikipedia | ~115 GB | Monthly |
| Stack Overflow | stack_exchange | ~75 GB | Yearly |
| Project Gutenberg | gutenberg | ~70 GB | Infrequent |
| Math Stack Exchange | stack_exchange | ~7 GB | Monthly |
| Wikibooks EN | wikibooks | ~5 GB | Monthly |
| Super User | stack_exchange | ~4 GB | Monthly |
| iFixit EN | ifixit | ~3 GB | Infrequent |
| Ask Ubuntu | stack_exchange | ~2.5 GB | Monthly |
| Unix & Linux SE | stack_exchange | ~1.2 GB | Monthly |
| Wikivoyage EN | wikivoyage | ~1 GB | Monthly |
| **Total** | | **~284 GB** | |

All ZIM files are downloaded from `https://download.kiwix.org/zim/<category>/`.

To add new sources, edit the `ZIM_CATALOG` array in `scripts/update-archive.sh`.
Browse available ZIMs at https://download.kiwix.org/zim/.

## Scripts

### scripts/update-archive.sh

Downloads and updates ZIM files on the Pi. Checks the Kiwix server for newer
versions and only downloads what's changed. Supports resume for interrupted
downloads.

**Copy to Pi and run:**

```bash
scp scripts/update-archive.sh chaseconover@chase-raspberrypi.local:/tmp/update-archive.sh
ssh chaseconover@chase-raspberrypi.local
tmux                    # So it survives SSH disconnection
sudo bash /tmp/update-archive.sh
```

**Options:**

```bash
# Dry run — show what would be downloaded without downloading
sudo bash /tmp/update-archive.sh --list

# Download sequentially — one at a time, progress bar in terminal
sudo bash /tmp/update-archive.sh --sequential

# Set parallel download count (default: 4)
sudo bash /tmp/update-archive.sh --parallel 6

# Download all 10 at once
sudo bash /tmp/update-archive.sh --parallel 10
```

**Monitoring parallel downloads:**

```bash
# Watch all download logs
tail -f /mnt/disk1/archive/logs/download-*.log

# Check .part file sizes growing
watch ls -lh /mnt/disk1/archive/kiwix/*.part
```

**How updates work:**

- ZIM filenames contain dates (e.g. `wikipedia_en_all_maxi_2026-02.zim`)
- The script scrapes the Kiwix directory listing to find the latest version
- If the latest version is already on disk, it's skipped
- New versions download alongside old ones (nothing is deleted)
- Old versions should be removed manually after verifying the new one works
- Downloads use `wget --continue` so interrupted downloads resume automatically
- The script downloads directly to the final `.zim` filename (no temp file) so that
  `--continue` works correctly. **Never use `wget -O` with `--continue`** — it
  truncates the file on retry and destroys partial downloads.

**Known issues:**

- `download.kiwix.org` redirects to mirrors. As of 2026-03, it often redirects to
  `ny.mirror.driftle.ss` which is dead. The script uses `ftp.fau.de` (German university)
  as the primary mirror instead.
- FAU does not mirror the Gutenberg collection. Use `ftp.nluug.nl` for Gutenberg:
  ```bash
  cd /mnt/disk1/archive/kiwix && sudo wget --continue --tries=20 --waitretry=10 \
    --progress=bar:force:noscroll \
    "https://ftp.nluug.nl/pub/kiwix/zim/gutenberg/gutenberg_en_all_2025-11.zim"
  ```
- If a mirror stops working, see alternative mirrors listed in the script header or
  browse https://download.kiwix.org/mirrors.html
- Always run long downloads inside `tmux` so they survive SSH disconnections. If the
  Pi crashes mid-download, `wget --continue` resumes from where it stopped (as long as
  you didn't use `-O`).
- Downloading too many files in parallel (6+) from a single mirror can trigger rate
  limiting or connection refusal. 4 parallel is a safe default.

### scripts/organize-media.sh

One-time script that reorganized `/mnt/disk1/media/movies/` into
Jellyfin-compatible structure. Already executed on 2026-03-30. Documented here
for reference only.

**What it did:**
- Moved TV shows (Better Call Saul, Rick and Morty, Futurama, Tom and Jerry,
  South Park) from `movies/` to `shows/` with proper `Show Name (Year)/Season XX/`
  naming
- Extracted 18+ movies that were buried inside other movie folders (e.g. Fight Club,
  Inception, and others were nested inside "The Princess Bride" folder)
- Split the Harry Potter 8-film collection into 8 individual movie folders
- Split the Lord of the Rings trilogy into 3 individual movie folders
- Separated Futurama's 4 movies from its TV episodes
- Moved loose files (Trolls, Hunter x Hunter, In Search of Greatness) into
  proper `Movie Name (Year)/` folders
- Moved a Super Mario 64 ROM to `/mnt/disk1/media/misc/`

No files were deleted. Empty original folders remain and can be cleaned up
manually.

## Kiwix Service

Kiwix Serve runs as a Docker container in the homelab stack.

**Service definition:** `platform/compose/services/kiwix.yml`
**Ansible registration:** `ansible/inventory/production/group_vars/all.yml` under `platform_services.kiwix`
**URL:** `https://archive.lab.chaseconover.com`
**Data directory:** `/mnt/disk1/archive/kiwix/` (mounted read-only)

The container uses `--monitorLibrary` which means it automatically detects new
ZIM files as they appear — no restart needed after downloading new content.

To deploy or redeploy:

```bash
./scripts/deploy deploy
```

## Media Organization

The media library at `/mnt/disk1/media/` follows Jellyfin naming conventions:

```
/mnt/disk1/media/
├── movies/                                    # One folder per movie
│   ├── Fight Club (1999)/
│   │   └── Fight.Club.10th.Anniversary.Edition.1999.1080p.BrRip.x264.YIFY.mp4
│   ├── The Lord of the Rings - The Fellowship of the Ring (2001)/
│   │   └── Lord_of_the_Rings_Fellowship_of_the_Ring_Ext_2001_1080p_BluRay_....mp4
│   └── ...
├── shows/                                     # Show Name (Year)/Season XX/
│   ├── Better Call Saul (2015)/Season 06/
│   ├── Futurama (1999)/Season 01/ ... Season 07/
│   ├── Rick and Morty (2013)/Season 01/ ... Season 04/
│   ├── South Park (1997)/Season 00/
│   └── Tom and Jerry (1940)/
├── music/                                     # (empty)
├── books/                                     # (empty)
├── photos/                                    # (empty)
└── misc/                                      # Non-media files
    └── Super Mario 64 HD FOR Windows (N64 rom+ HD Texture Addon)/
```

## Future: AI Search Over the Archive

ZIM files are compatible with several local AI integration tools. The plan is to
add AI-powered search over the archive content in a future phase.

### Recommended approach

**Phase 1 — Direct ZIM search (keyword-based):**
Use OpenZIM MCP or llm-tools-kiwix to expose ZIM files to AI tools. No
extraction needed — the AI queries ZIM files at runtime.

- [OpenZIM MCP](https://github.com/cameronrye/openzim-mcp) — MCP server that
  exposes ZIM files to Claude Desktop, Cursor, or any MCP client. Most polished
  option. 18 specialized tools for search, navigation, content retrieval.
- [llm-tools-kiwix](https://github.com/mozanunal/llm-tools-kiwix) — Plugin for
  the `llm` CLI. Auto-discovers ZIM files, lightweight.
- [Hermit-AI](https://github.com/imDelivered/Hermit-AI) — Turnkey offline AI
  chatbot that reads ZIM files directly via Ollama. Includes a tool (Forge) to
  convert PDFs into ZIM format.

**Phase 2 — Semantic search (vector database):**
Extract ZIM content to text, embed into a vector database for conceptual search.

- [zim-llm](https://github.com/rouralberto/zim-llm) — Automates the pipeline:
  ZIM → text extraction → chunking → embeddings → ChromaDB/FAISS.
- Embedding model: `all-MiniLM-L6-v2` (~80MB, runs on CPU, ARM64 compatible)
- Vector DB: Qdrant in SQLite-backed mode (no daemon, low RAM)
- LLM: Ollama running a small model (1.5B-3B parameters for Pi)

**Phase 3 — Full local AI assistant:**
Combine the search layer with a local LLM and a chat UI.

- [Open WebUI](https://github.com/open-webui/open-webui) — ChatGPT-like
  interface with built-in RAG and 9 vector DB options
- [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm) — Desktop app,
  drag-and-drop documents, zero-config RAG

### Architecture for AI search

```
ZIM Files (source of truth)
    |
    +-- Kiwix Serve (web UI for human browsing)
    |
    +-- OpenZIM MCP (direct keyword search for AI tools)
    |
    +-- zim-llm (extract → embed → Qdrant for semantic search)
    |
    +-- Ollama (local LLM inference)
    |
    +-- Open WebUI (chat interface)
```

The extracted text would live at `/mnt/disk1/archive/extracted/` and the vector
database index at `/mnt/disk1/archive/index/`. These are generated locally from
the ZIM files and can be regenerated at any time.

### Hardware considerations

The Raspberry Pi (8GB or 16GB RAM) can handle:
- Kiwix Serve + MCP search: easily
- Vector DB (Qdrant SQLite mode): ~200MB RAM spikes, ~3s per query
- Embeddings (MiniLM-L6-v2): runs on CPU, ARM64 compatible
- LLM inference: limited to 1.5B parameter models. For larger models, offload
  to a more powerful machine on the network.
