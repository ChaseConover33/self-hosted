#!/usr/bin/env bash
#
# organize-media.sh
#
# Reorganizes /mnt/disk1/media/ into Jellyfin-compatible structure.
# All operations are `mv` on the same filesystem — no data is copied,
# just directory entries updated. No files are deleted.
#
# Run on the Raspberry Pi as: sudo bash /tmp/organize-media.sh
# (sudo needed because files are owned by root)

set -euo pipefail

MOVIES="/mnt/disk1/media/movies"
SHOWS="/mnt/disk1/media/shows"
MISC="/mnt/disk1/media/misc"

echo "=== Phase 1: Create target directories ==="

# TV show directories (Jellyfin naming: Show Name (Year)/Season XX/)
mkdir -p "$SHOWS/Better Call Saul (2015)/Season 06"
mkdir -p "$SHOWS/Rick and Morty (2013)/Season 01"
mkdir -p "$SHOWS/Rick and Morty (2013)/Season 02"
mkdir -p "$SHOWS/Rick and Morty (2013)/Season 03"
mkdir -p "$SHOWS/Rick and Morty (2013)/Season 04"
mkdir -p "$SHOWS/Futurama (1999)/Season 01"
mkdir -p "$SHOWS/Futurama (1999)/Season 02"
mkdir -p "$SHOWS/Futurama (1999)/Season 03"
mkdir -p "$SHOWS/Futurama (1999)/Season 04"
mkdir -p "$SHOWS/Futurama (1999)/Season 05"
mkdir -p "$SHOWS/Futurama (1999)/Season 06"
mkdir -p "$SHOWS/Futurama (1999)/Season 07"
mkdir -p "$SHOWS/Tom and Jerry (1940)"
mkdir -p "$SHOWS/South Park (1997)/Season 00"

# Misc (non-media content)
mkdir -p "$MISC"

# Movie directories for films trapped inside other folders
mkdir -p "$MOVIES/Bad Times at the El Royale (2018)"
mkdir -p "$MOVIES/Christopher Robin (2018)"
mkdir -p "$MOVIES/Captain America - The First Avenger (2011)"
mkdir -p "$MOVIES/Monsters Inc (2001)"
mkdir -p "$MOVIES/Searching (2018)"
mkdir -p "$MOVIES/District 9 (2009)"
mkdir -p "$MOVIES/Shazam (2019)"
mkdir -p "$MOVIES/Solo - A Star Wars Story (2018)"
mkdir -p "$MOVIES/Avengers - Age of Ultron (2015)"
mkdir -p "$MOVIES/Inception (2010)"
mkdir -p "$MOVIES/Batman v Superman - Dawn of Justice (2016)"
mkdir -p "$MOVIES/Mid90s (2018)"
mkdir -p "$MOVIES/Fight Club (1999)"
mkdir -p "$MOVIES/Glass (2019)"
mkdir -p "$MOVIES/Halloween (2018)"
mkdir -p "$MOVIES/Avengers - Endgame (2019)"
mkdir -p "$MOVIES/Boogie Nights (1997)"
mkdir -p "$MOVIES/Midnight in Paris (2011)"
mkdir -p "$MOVIES/One Flew Over the Cuckoos Nest (1975)"
mkdir -p "$MOVIES/The Princess Bride (1987)"
mkdir -p "$MOVIES/Hunter x Hunter - Phantom Rouge (2013)"
mkdir -p "$MOVIES/In Search of Greatness (2018)"
mkdir -p "$MOVIES/Trolls (2016)"

# Harry Potter — split from bundle into individual folders
mkdir -p "$MOVIES/Harry Potter and the Philosophers Stone (2001)"
mkdir -p "$MOVIES/Harry Potter and the Chamber of Secrets (2002)"
mkdir -p "$MOVIES/Harry Potter and the Prisoner of Azkaban (2004)"
mkdir -p "$MOVIES/Harry Potter and the Goblet of Fire (2005)"
mkdir -p "$MOVIES/Harry Potter and the Order of the Phoenix (2007)"
mkdir -p "$MOVIES/Harry Potter and the Half-Blood Prince (2009)"
mkdir -p "$MOVIES/Harry Potter and the Deathly Hallows Part 1 (2010)"
mkdir -p "$MOVIES/Harry Potter and the Deathly Hallows Part 2 (2011)"

# LOTR — split from trilogy bundle into individual folders
mkdir -p "$MOVIES/The Lord of the Rings - The Fellowship of the Ring (2001)"
mkdir -p "$MOVIES/The Lord of the Rings - The Two Towers (2002)"
mkdir -p "$MOVIES/The Lord of the Rings - The Return of the King (2003)"

# Futurama movies
mkdir -p "$MOVIES/Futurama - Benders Big Score (2007)"
mkdir -p "$MOVIES/Futurama - The Beast with a Billion Backs (2008)"
mkdir -p "$MOVIES/Futurama - Benders Game (2008)"
mkdir -p "$MOVIES/Futurama - Into the Wild Green Yonder (2009)"

echo "=== Phase 2: Move TV shows out of movies/ ==="

# --- Better Call Saul (Season 6 only) ---
# Some episodes are in subdirectories, some are loose in Season 6/
# Move the whole Season 6 contents
for f in "$MOVIES/Better Call Saul/Season 6/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Better Call Saul (2015)/Season 06/"
done
# Episodes inside nested subdirectories (S06E01-E04 have extra folder nesting)
for d in "$MOVIES/Better Call Saul/Season 6/"*/; do
  [ -d "$d" ] || continue
  for f in "$d"*.mkv; do
    [ -f "$f" ] && mv "$f" "$SHOWS/Better Call Saul (2015)/Season 06/"
  done
done

# --- Rick and Morty (Seasons 1-4) ---
for f in "$MOVIES/Rick and Morty/Rick and Morty - Season 1/"*.mp4; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Rick and Morty (2013)/Season 01/"
done
for f in "$MOVIES/Rick and Morty/Rick and Morty - Season 2/"*.mp4; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Rick and Morty (2013)/Season 02/"
done
for f in "$MOVIES/Rick and Morty/Rick and Morty - Season 3/"*.mp4; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Rick and Morty (2013)/Season 03/"
done
for f in "$MOVIES/Rick and Morty/Rick and Morty - Season 4/"*.mp4; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Rick and Morty (2013)/Season 04/"
done
# Stray S04E03 episode in its own top-level folder
mv "$MOVIES/Rick.and.Morty.S04E03.1080p.WEBRip.x264-TBS[TGx]/rick.and.morty.s04e03.1080p.webrip.x264-tbs.mkv" \
   "$SHOWS/Rick and Morty (2013)/Season 04/" 2>/dev/null || true

# --- Futurama (S01-S07 + loose S02E19) ---
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S01/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 01/"
done
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S02/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 02/"
done
# Loose S02E19 file at the root of the Futurama folder
mv "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/Futurama.S02E19.DVDRip.x265-HETeam.mkv" \
   "$SHOWS/Futurama (1999)/Season 02/" 2>/dev/null || true
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S03/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 03/"
done
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S04/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 04/"
done
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S05/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 05/"
done
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S06/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 06/"
done
for f in "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/S07/"*.mkv; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Futurama (1999)/Season 07/"
done

# Futurama movies — these are films, not episodes
mv "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/Movies/Futurama.Benders.Big.Score.2007.720p.WEB-DL.x265-HETeam.mkv" \
   "$MOVIES/Futurama - Benders Big Score (2007)/" 2>/dev/null || true
mv "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/Movies/Futurama.The.Beast.with.a.Billion.Backs.720p.WEB-DL.x265-HETeam.mkv" \
   "$MOVIES/Futurama - The Beast with a Billion Backs (2008)/" 2>/dev/null || true
mv "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/Movies/Futurama.Bender's.Game.2008.720p.BluRay.x265-HETeam.mkv" \
   "$MOVIES/Futurama - Benders Game (2008)/" 2>/dev/null || true
mv "$MOVIES/Futurama.COMPLETE.S01-S07.720p.BluRay.x265-HETeam/Movies/Futurama.Into.The.Wild.Green.Yonder.2009.720p.BluRay.x265-HETeam.mkv" \
   "$MOVIES/Futurama - Into the Wild Green Yonder (2009)/" 2>/dev/null || true

# --- Tom and Jerry (move entire collection as-is) ---
# Tom and Jerry episodes are numbered files — move them all into the show folder.
# We'll keep the flat structure since they don't have season/episode info that maps cleanly.
for f in "$MOVIES/Tom and Jerry Cartoons Complete Collection (1940-2007) [DVDRip] M8/"*.avi; do
  [ -f "$f" ] && mv "$f" "$SHOWS/Tom and Jerry (1940)/"
done

# --- South Park special ---
mv "$MOVIES/South.Park.S00E42.The.Pandemic.Special.1080p.AAC.2.0-PRiCK[TGx]/South.Park.S00E42.The.Pandemic.Special.1080p.AAC.2.0-PRiCK.mkv" \
   "$SHOWS/South Park (1997)/Season 00/" 2>/dev/null || true

echo "=== Phase 3: Extract movies buried inside other movie folders ==="

# --- Movies inside "The Princess Bride (1987) DVDrip xvid/" ---
PB="$MOVIES/The Princess Bride (1987) DVDrip xvid"

mv "$PB/Bad Times At The El Royale (2018) [WEBRip] [1080p] [YTS.AM]/Bad.Times.At.The.El.Royale.2018.1080p.WEBRip.x264-[YTS.AM].mp4" \
   "$MOVIES/Bad Times at the El Royale (2018)/" 2>/dev/null || true

mv "$PB/Christopher Robin (2018) [BluRay] [1080p] [YTS.AM]/Christopher.Robin.2018.1080p.BluRay.x264-[YTS.AM].mp4" \
   "$MOVIES/Christopher Robin (2018)/" 2>/dev/null || true

mv "$PB/Captain America - The First Avenger (2011)/Captain.America.The.First.Avenger.1080p.BrRip.x264.YIFY.mp4" \
   "$MOVIES/Captain America - The First Avenger (2011)/" 2>/dev/null || true

mv "$PB/Monsters Inc (2001) [1080p]/Monsters.Inc.2001.1080p.BrRip.x264.YIFY.mp4" \
   "$MOVIES/Monsters Inc (2001)/" 2>/dev/null || true

mv "$PB/Harry Potter and the Deathly Hallows Part 1 (2010) [1080p]/Harry.Potter.and.the.Deathly.Hallows.Part.1.2010.1080p.BrRip.x264.YIFY.mp4" \
   "$MOVIES/Harry Potter and the Deathly Hallows Part 1 (2010)/" 2>/dev/null || true

mv "$PB/Searching.2018.HC.HDRip.XviD.AC3-EVO/Searching.2018.HC.HDRip.XviD.AC3-EVO.avi" \
   "$MOVIES/Searching (2018)/" 2>/dev/null || true

mv "$PB/District 9 (2009) [1080p]/District.9.2009.1080p.BluRay.x264.YIFY.mp4" \
   "$MOVIES/District 9 (2009)/" 2>/dev/null || true

mv "$PB/Shazam.2019.1080p.V2.HC.HDRip.X264-EVO[TGx]/Shazam.2019.1080p.V2.HC.HDRip.X264-EVO.mkv" \
   "$MOVIES/Shazam (2019)/" 2>/dev/null || true

mv "$PB/Solo A Star Wars Story (2018) [BluRay] [1080p] [YTS.AM]/Solo.A.Star.Wars.Story.2018.1080p.BluRay.x264-[YTS.AM].mp4" \
   "$MOVIES/Solo - A Star Wars Story (2018)/" 2>/dev/null || true

mv "$PB/Avengers Age of Ultron (2015) [1080p]/Avengers.Age.of.Ultron.2015.1080p.BluRay.x264.YIFY.mp4" \
   "$MOVIES/Avengers - Age of Ultron (2015)/" 2>/dev/null || true

mv "$PB/Inception (2010) [1080p]/Inception.2010.1080p.BrRip.x264.YIFY.mp4" \
   "$MOVIES/Inception (2010)/" 2>/dev/null || true

mv "$PB/Batman V Superman Dawn Of Justice (2016) [1080p] [YTS.AG]/Batman.V.Superman.Dawn.Of.Justice.2016.1080p.BluRay.x264-[YTS.AG].mp4" \
   "$MOVIES/Batman v Superman - Dawn of Justice (2016)/" 2>/dev/null || true

mv "$PB/The Princess Bride (1987) DVDrip xvid.avi" \
   "$MOVIES/The Princess Bride (1987)/" 2>/dev/null || true

mv "$PB/Mid90s (2018) [WEBRip] [1080p] [YTS.AM]/Mid90s.2018.1080p.WEBRip.x264-[YTS.AM].mp4" \
   "$MOVIES/Mid90s (2018)/" 2>/dev/null || true

mv "$PB/Fight Club (1999) [1080p]/Fight.Club.10th.Anniversary.Edition.1999.1080p.BrRip.x264.YIFY.mp4" \
   "$MOVIES/Fight Club (1999)/" 2>/dev/null || true

mv "$PB/Glass 2019.HDCAM.XViD.AC3-ETRG/Glass 2019 .HDCAM.XViD.AC3-ETRG.avi" \
   "$MOVIES/Glass (2019)/" 2>/dev/null || true

mv "$PB/Halloween (2018) [WEBRip] [1080p] [YTS.AM]/Halloween.2018.1080p.WEBRip.x264-[YTS.AM].mp4" \
   "$MOVIES/Halloween (2018)/" 2>/dev/null || true

mv "$PB/Avengers.Endgame.2019.1080p.HC.YG/Avengers.Endgame.2019.1080p.HC.HDTS.H264.AC3.YG.mkv" \
   "$MOVIES/Avengers - Endgame (2019)/" 2>/dev/null || true

mv "$PB/Boogie Nights (1997)/Boogie.Nights.1997.720p.BluRay.x264.YIFY.mkv" \
   "$MOVIES/Boogie Nights (1997)/" 2>/dev/null || true

mv "$PB/Midnight In Paris (2011)/Midnight.in.Paris.2011.720p.BrRip.x264.mp4" \
   "$MOVIES/Midnight in Paris (2011)/" 2>/dev/null || true

# --- One Flew Over The Cuckoo's Nest inside "It (2017)" ---
mv "$MOVIES/It (2017) [YTS.AG]/One Flew Over The Cuckoo's Nest (1975) [1080p]/One.Flew.Over.The.Cuckoo's.Nest.1080p.BrRip.x264.YIFY.mp4" \
   "$MOVIES/One Flew Over the Cuckoos Nest (1975)/" 2>/dev/null || true

echo "=== Phase 4: Split multi-movie bundles ==="

# --- Harry Potter 8-film collection ---
HP="$MOVIES/Harry.Potter.The.Complere.8-Film.Collection.BDRip.720p.x264.aac.2.0"

mv "$HP/1. Harry Potter and the Philosopher's Stone (2001)/Harry.Potter.And.The.Philosopher's.Stone.2001.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Philosophers Stone (2001)/" 2>/dev/null || true

mv "$HP/2. Harry Potter and the Chamber of Secrets (2002)/Harry.Potter.And.The.Chamber.Of.Secrets.2002.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Chamber of Secrets (2002)/" 2>/dev/null || true

mv "$HP/3. Harry Potter and the Prisoner of Azkaban (2004)/Harry.Potter.And.The.Prisoner.Of.Azkaban.2004.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Prisoner of Azkaban (2004)/" 2>/dev/null || true

mv "$HP/4. Harry Potter and the Goblet of Fire (2005)/Harry.Potter.And.The.Goblet.Of.Fire.2005.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Goblet of Fire (2005)/" 2>/dev/null || true

mv "$HP/5. Harry Potter and the Order of the Phoenix (2007)/Harry.Potter.And.The.Order.Of.The.Phoenix.2007.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Order of the Phoenix (2007)/" 2>/dev/null || true

mv "$HP/6. Harry Potter and the Half-Blood Prince (2009)/Harry.Potter.And.The.Half-blood.Prince.2009.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Half-Blood Prince (2009)/" 2>/dev/null || true

mv "$HP/7. Harry Potter and the Deathly Hallows Part 1 (2010)/Harry.Potter.And.The.Deathly.Hallows.Part.1.2010.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Deathly Hallows Part 1 (2010)/" 2>/dev/null || true

mv "$HP/8. Harry Potter and the Deathly Hallows Part 2 (2011)/Harry.Potter.And.The.Deathly.Hallows.Part.2.2011.BDRip.720p.mkv" \
   "$MOVIES/Harry Potter and the Deathly Hallows Part 2 (2011)/" 2>/dev/null || true

# Loose HP files that are duplicates of the collection — move into the same folders
mv "$MOVIES/Harry Potter And The Deathly Hallows Part 1 (2010)/HP7.2010.BRRip.720p.Bluray.YIFY.mkv" \
   "$MOVIES/Harry Potter and the Deathly Hallows Part 1 (2010)/" 2>/dev/null || true

mv "$MOVIES/Harry Potter And The Deathly Hallows Part 2 (2011)/Harry.Potter.And.The.Deathly.Hallows.Part.2.2011.720p.BrRip.264.YIFY.mkv-muxed.mp4" \
   "$MOVIES/Harry Potter and the Deathly Hallows Part 2 (2011)/" 2>/dev/null || true

mv "$MOVIES/Harry_Potter_and_the_Half_Blood_Prince_2009.mkv" \
   "$MOVIES/Harry Potter and the Half-Blood Prince (2009)/" 2>/dev/null || true

# --- Lord of the Rings trilogy ---
LOTR="$MOVIES/Lord of the Rings Trilogy BluRay Extended 1080p QEBS5 AAC51 PS3 MP4-FASM"

mv "$LOTR/Lord_of_the_Rings_Fellowship_of_the_Ring_Ext_2001_1080p_BluRay_QEBS5_AAC51_PS3_MP4-FASM.mp4" \
   "$MOVIES/The Lord of the Rings - The Fellowship of the Ring (2001)/" 2>/dev/null || true

mv "$LOTR/Lord_of_the_Rings_Two_towers_Ext_2002_1080p_BluRay_QEBS5_AAC51_PS3_MP4-FASM.mp4" \
   "$MOVIES/The Lord of the Rings - The Two Towers (2002)/" 2>/dev/null || true

mv "$LOTR/Lord_of_the_Rings_Return_of_the_King_Ext_2003_1080p_BluRay_QEBS5_AAC51_PS3_MP4-FASM.mp4" \
   "$MOVIES/The Lord of the Rings - The Return of the King (2003)/" 2>/dev/null || true

# Move sample files into the corresponding movie folders too
mv "$LOTR/sample/Lord_of_the_Rings_Fellowship_of_the_Ring_Ext_2001_1080p_BluRay_QEBS5_AAC51_PS3_MP4-FASM-sample.mp4" \
   "$MOVIES/The Lord of the Rings - The Fellowship of the Ring (2001)/" 2>/dev/null || true

mv "$LOTR/sample/Lord_of_the_Rings_Two_towers_Ext_2002_1080p_BluRay_QEBS5_AAC51_PS3_MP4-FASM-sample.mp4" \
   "$MOVIES/The Lord of the Rings - The Two Towers (2002)/" 2>/dev/null || true

mv "$LOTR/sample/Lord_of_the_Rings_Return_of_the_King_Ext_2003_1080p_BluRay_QEBS5_AAC51_PS3_MP4-FASM-sample.mp4" \
   "$MOVIES/The Lord of the Rings - The Return of the King (2003)/" 2>/dev/null || true

echo "=== Phase 5: Move loose files into proper folders ==="

mv "$MOVIES/Trolls.2016.1080p-dual-lat.mp4" \
   "$MOVIES/Trolls (2016)/" 2>/dev/null || true

mv "$MOVIES/[DeadFish] Hunter x Hunter_ Phantom Rouge - Movie [BD][1080p][AAC].mp4" \
   "$MOVIES/Hunter x Hunter - Phantom Rouge (2013)/" 2>/dev/null || true

mv "$MOVIES/In.Search.of.Greatness.2018.1080p.WEB.x264-worldmkv.mkv" \
   "$MOVIES/In Search of Greatness (2018)/" 2>/dev/null || true

echo "=== Phase 6: Move non-media to misc ==="

mv "$MOVIES/Super Mario 64 HD FOR Windows (N64 rom+ HD Texture Addon)" \
   "$MISC/" 2>/dev/null || true

echo ""
echo "=== Done! ==="
echo ""
echo "Old empty folders remain in place (nothing was deleted)."
echo "You can review and remove them manually when ready."
echo ""
echo "Summary of changes:"
echo "  - TV shows moved to $SHOWS/"
echo "  - 18+ movies extracted from nested folders"
echo "  - Harry Potter split into 8 individual folders"
echo "  - LOTR split into 3 individual folders"
echo "  - Futurama movies separated from episodes"
echo "  - Loose files organized into proper folders"
echo "  - Super Mario 64 moved to $MISC/"
