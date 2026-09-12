# Video_Convert_2

A collection of bash scripts to batch re-encode video files into portable MP4 format, suitable for playback on any Smart TV or media server (works great with Plex/Serviio).

The default output is **HEVC Main 10** (`hvc1`-tagged) with stereo AAC. That direct-plays on current TVs, phones and desktop clients, but it is a stronger requirement than the H.264 these scripts used to emit — if you serve older or unusual clients, verify direct play before converting a library, since a client that cannot decode it makes the *server* transcode. AV1 is deliberately not used for this reason.

Make sure to compare the input video with the output using `mediainfo`. You may be surprised by the results — the output is often better quality than the input.

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `vc2.sh` | Main batch video converter (auto-detects NVIDIA GPU) |
| `vc1.sh` | Single-file converter, tuned for compression or quality |
| `cc_probe.sh` | Helper: probe video file and output stream info |
| `cc_norm.sh` | Helper: analyze audio and output loudnorm parameters |
| `vc_rename.sh` | Utility: normalize video filenames |
| `tools/build-ffmpeg.sh` | Rebuild the `/usr/local` ffmpeg these scripts depend on |

---

## vc2.sh — Batch Video Converter

Searches a configured directory for video files, probes each one, normalizes audio, and re-encodes to MP4. Automatically uses NVIDIA hardware acceleration (`hevc_nvenc`) when an NVIDIA GPU is detected; falls back to `libx265` software encoding otherwise. The software path needs a **multilib x265** — against an 8-bit-only build the 10-bit output silently degrades.

### Synopsis

    vc2.sh [OPTION...]

### Options

    -h, --help        This documentation.

    --hq              High quality override: 60fps, QF=0.2, 192k audio,
                      slow preset, no resize.

    --lq              Low quality override: 23.976fps, QF=0.08, 128k audio,
                      fast preset, with resize.

    --no-gpu          Disable hardware acceleration even if an NVIDIA GPU
                      is detected; forces libx265 software encoding.

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

The Preset column applies to the **CPU** encoder only. NVENC uses its own `p1`–`p7` scale (`nvenc_preset`, default `p6`) — x264's preset names mean something quite different there, and passing them selects NVENC's legacy table.

Quality Factor is a **rate ceiling**, not a target: it sizes `-maxrate`/`-bufsize`, while `nvenc_cq` / `cpu_crf` decide the actual quality and the encoder spends less on easy content.

The rate ceiling is calculated dynamically from the quality factor: `ceiling = QF × width × height × FPS / 1000`, with `-maxrate` at 1.5x and `-bufsize` at 2x that.  
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

Re-encodes one video file for either optimal compression or optimal quality. Defaults to HEVC on NVENC; `-hwaccel cuda` lets ffmpeg pick NVDEC per stream and fall back to software for codecs the GPU cannot decode.

    vc1.sh [options] <inFile>

| Option | Meaning |
|--------|---------|
| `-m, --mode compression\|quality` | Quality intent (default: `compression`) |
| `-c, --cpu` | Encode with libx265 instead of hevc_nvenc |
| `--av1` | Encode AV1 with SVT-AV1 (implies `--cpu`) |
| `-s, --original-size` | Do not cap width at 1280px |
| `--max-width N` | Change the width cap |
| `--fps N` | Frame rate cap (default `24000/1001`); `none` to disable |
| `-q, --cq N` | Override the quality level |
| `--mp4` | Write MP4 instead of MKV |
| `--verify` | Score the result against the source with VMAF |
| `-n, --dry-run` | Print the ffmpeg command and exit |
| `-o, --output FILE` | Output path |

Output defaults to `<basename>_recode.mkv`. Quality ladder:

| Mode | hevc_nvenc | libx265 | libsvtav1 |
|------|:----------:|:-------:|:---------:|
| compression | cq 29 | crf 26 (slow) | crf 34 (preset 6) |
| quality | cq 24 | crf 20 (slow) | crf 28 (preset 5) |

The frame rate is *capped*, never forced, so 23.976fps and slower sources pass through untouched. Nothing is ever upscaled. Subtitles, chapters and metadata are carried through.

Measured on 30s of 720p, SSIM against a common reference: compression mode 1419 kb/s @ 0.98937, quality mode 2739 kb/s @ 0.99362. `--av1` gives the best quality-per-byte (1254 kb/s @ 0.99119) and is roughly 3x faster than `--cpu`, but is not widely direct-played — see the note at the top of this file.

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

---

## tools/build-ffmpeg.sh — ffmpeg Builder

Rebuilds the hand-compiled ffmpeg in `/usr/local` that these scripts call directly. Records the exact configure line, so the encoder features `vc1.sh` and `vc2.sh` rely on (SVT-AV1, libvmaf, `scale_cuda`, multilib x265) are reproducible rather than folklore.

    tools/build-ffmpeg.sh

Honours `BUILD_ROOT`, `PREFIX` and `X265_TAG` from the environment. Ends with a dozen self-checks that assert each feature by actually encoding with it.

Two findings baked into it, both of which cost real time to diagnose:

- **`--enable-cuda-nvcc` cannot be used** on a current Fedora. CUDA 12.9 refuses gcc 15 outright, and against gcc-14 it collides with glibc 2.42's C23 `sinpi`/`cospi`/`tanpi`. `--enable-cuda-llvm` builds the same filters via clang's NVPTX backend and needs no CUDA toolkit at all. `--enable-libnpp` is also gone — upstream removed it, so `scale_npp` no longer exists.
- **x265 must be built from a real, reachable git tag.** Its CMakeLists guards the shared-library install with `# shared library is not installed if a tag is not found`, so a tagless *or shallow* checkout installs only `libx265.a` and silently leaves the previous `.so` in place. The symptom is an ffmpeg that still reports 8-bit-only x265 after an apparently successful multilib build, and an `HEVC encoder version unknown` banner.
