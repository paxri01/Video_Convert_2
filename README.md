# Video_Convert_2

A collection of bash scripts to batch re-encode video files into portable MP4 format, suitable for playback on any Smart TV or media server (works great with Plex/Serviio). The default settings produce files that play on virtually any device without transcoding.

Make sure to compare the input video with the output using `mediainfo`. You may be surprised by the results — the output is often better quality than the input.

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `vc2.sh` | Main batch video converter (auto-detects NVIDIA GPU) |
| `vc1.sh` | Single-file converter (experimental) |
| `cc_probe.sh` | Helper: probe video file and output stream info |
| `cc_norm.sh` | Helper: analyze audio and output loudnorm parameters |
| `vc_rename.sh` | Utility: normalize video filenames |

---

## vc2.sh — Batch Video Converter

Searches a configured directory for video files, probes each one, normalizes audio, and re-encodes to MP4. Automatically uses NVIDIA hardware acceleration (`h264_nvenc`) when an NVIDIA GPU is detected; falls back to `libx264` software encoding otherwise.

### Synopsis

    vc2.sh [OPTION...]

### Options

    -h, --help        This documentation.

    --hq              High quality override: 60fps, QF=0.2, 192k audio,
                      slow preset, no resize.

    --lq              Low quality override: 23.976fps, QF=0.08, 128k audio,
                      fast preset, with resize.

    --no-gpu          Disable hardware acceleration even if an NVIDIA GPU
                      is detected; forces libx264 software encoding.

    -m, --movie       Feature-length movies  (searches: renamed/features/)
    --mv              Music videos           (searches: renamed/mtv/)
    -o, --other       Other video files      (searches: renamed/other/)
    -s, --series      TV series episodes     (searches: renamed/series/)
    -v, --video       Generic video files    (searches: renamed/video/)
    -x, --restrict    Restricted videos      (searches: renamed/restricted/)

### Per-type Encoding Settings

| Type | FPS | Quality Factor | Audio Bitrate | Preset | Resize |
|------|-----|:--------------:|:-------------:|:------:|:------:|
| movie | 23.976 | 0.10 | 160k | medium | yes |
| mv | 30 | 0.20 | 192k | slow | yes |
| other | 23.976 | 0.10 | 160k | slow | yes |
| series | 23.976 | 0.08 | 128k | fast | yes |
| video | 30 | 0.20 | 192k | slow | no |
| restricted | 25 | 0.08 | 92k | fast | yes |

Video bitrate is calculated dynamically from the quality factor: `bitrate = QF × width × height × FPS / 1000`.  
Resize: videos wider than 1280px are scaled down to 1280px; narrower than 720px are scaled up to 720px.

### Examples

    # Re-encode TV series at default quality
    vc2.sh -s

    # Re-encode movies at high quality
    vc2.sh -m --hq

    # Re-encode series with hardware acceleration disabled
    vc2.sh -s --no-gpu

---

## vc1.sh — Single-File Converter

Re-encodes a single video file. Auto-detects NVIDIA GPU and uses hardware acceleration when available.

    vc1.sh <inFile>

Output is written to `<basename>_recode.mp4` in the current directory.

Supported input codecs for hardware decoding: h264, hevc, av1, vp8, vp9, mpeg1, mpeg2, mpeg4, vc1, mjpeg. Falls back to software decode + NVENC encode for other codecs, or full software encode when no GPU is available.

---

## cc_probe.sh — Video Probe Helper

Probes a video file with `ffprobe` and writes a `.probe.rc` file containing stream variables sourced by the encoder scripts.

    cc_probe.sh <inFile>

Output variables include: `fName`, `fSize`, `duration`, `vWidth`, `vHeight`, `vBitrate`, `vCodec`, `vFPS`, `vLanguage`, `vMap`, `mainVideo`, `aBitrate`, `aChannels`, `aCodec`, `aLanguage`, `aMap`, `aSamplerate`, `mainAudio`, `sMap`.

Stream selection logic:
- **Video**: prefers the default-flagged stream; falls back to the first video stream.
- **Audio**: prefers the default English stream, then first English stream, then first stream found.
- **Subtitles**: maps all English subtitle streams; skips unsupported formats (PGS, DVD, DVB, WEBVTT).

---

## cc_norm.sh — Audio Normalization Helper

Two-pass EBU R128 loudness normalization using `ffmpeg`'s `loudnorm` filter. Called automatically by `vc2.sh` and `vc2_hwaccel.sh`.

    cc_norm.sh <inFile> [ffmpeg_bin] [sample_range]

Targets: `-24.0` LUFS integrated, `-2.0` dBTP true peak, `11.0` LRA.  
Default sample range: `-ss 01:00 -t 06:00` (analyze 6 minutes starting at 1 minute).  
Outputs the `-filter:a loudnorm=...` string for use in the final encode pass.

---

## vc_rename.sh — Filename Normalizer

Normalizes video filenames in the current directory: converts to lowercase, replaces spaces with dots, and strips known site-watermark suffixes.

    # Dry run — shows what would be renamed without making changes
    vc_rename.sh

    # Actually rename the files
    vc_rename.sh 1

For unrecognized suffixes the script prompts interactively: move the suffix to a prefix, trim it, or leave the filename unchanged.

Supported file types: `.mkv`, `.mp4`, `.wmv`, `.webm`.

---

## Directory Structure

Expected input layout under `baseDir` (`/data2/usenet` by default):

    renamed/
    ├── features/          (-m / --movie)
    ├── mtv/               (--mv)
    ├── other/             (-o / --other)
    ├── restricted/        (-x / --restrict)
    ├── series/            (-s / --series)
    │   ├── Show Name 1/
    │   │   ├── S01/
    │   │   └── S02/
    │   └── Show Name 2/
    │       └── S01/
    └── video/             (-v / --video)

Output is written to `videoDir` (`/video` by default), mirroring the source directory structure.  
Processed source files are moved to `doneDir` (`/data2/usenet/done`).

---

## Requirements

- `ffmpeg` built with `libfdk_aac` and `libx264` (for CPU encoding)
- `ffprobe` (bundled with ffmpeg)
- `mediainfo`
- `jq` (used by `cc_norm.sh`)
- `bc`, `awk`, `numfmt` (standard utilities)
- NVIDIA drivers + NVENC-capable GPU (optional, for `--cuda` / hwaccel scripts)

The default audio codec is `libfdk_aac` and the default video codec is `libx264`. These can be changed in the script settings, but parameter tuning may also be required.

## Setup

Symlink the helper scripts into `/usr/local/bin` (without the `.sh` extension) so `vc2.sh` can find them:

    ln -s /path/to/cc_probe.sh /usr/local/bin/cc_probe
    ln -s /path/to/cc_norm.sh  /usr/local/bin/cc_norm
    ln -s /path/to/vc2.sh      /usr/local/bin/vc2

Ensure `/usr/local/bin` is in your `$PATH`.

## Logs

- Main log: `/var/log/convert/ccvc.log`
- Trace log: `/var/log/convert/ccvc_trace_<date>.log`

---

## Example Output

    > vc2 -s

    Starting run of Video Converter 2
      Collecting list of files to process....................................................[  OK  ]

    File 1 of 16
      Processing: series/TV Show/S02/S02E07.Episode 07.......................................[  OK  ]
      Normalizing audio track................................................................[  OK  ]
      Setting encode filters.................................................................[  OK  ]
                                           total time=01:27:46.69
    frame=126273 fps=236 q=27.0 Lsize= 1226065kB time=01:27:46.66 bitrate=1907.1kbits/s speed=9.83x
    ---------------------------
    Orig Size: 1.9GiB // New Size: 1.2GiB // File decreased by 35.18%
    ---------------------------
      Done

---

\- Cheers,

Rick
