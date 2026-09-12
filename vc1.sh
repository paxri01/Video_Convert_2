#!/bin/bash

## DESCRIPTION: Re-encode a single video for optimal compression or optimal quality.
##
## Defaults to HEVC on NVENC, which measured ~14% larger than x265 at equal SSIM
## while running 6.5x faster. Use --cpu for x265 or --av1 for SVT-AV1 when the
## extra time is worth the bytes.

set -uo pipefail

scriptDir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ffmpeg_bin=/usr/local/bin/ffmpeg
ffprobe_bin=/usr/local/bin/ffprobe

# Defaults
mode='compression'
useCPU=false
useAV1=false
originalSize=false
targetFPS='24000/1001'
maxWidth=1280
cqOverride=''
container='mkv'
verify=false
dryRun=false
outFile=''
aBitrateTarget='160k'

usage () {
  cat << EOF
Usage: ${0##*/} [options] <input file>

  -m, --mode MODE       compression (default) | quality
  -c, --cpu             encode with libx265 instead of hevc_nvenc
      --av1             encode AV1 with SVT-AV1 (implies --cpu)
  -s, --original-size   do not cap width at ${maxWidth}px
      --max-width N     change the width cap (default ${maxWidth})
      --fps N           frame rate cap (default ${targetFPS}); "none" to disable
  -q, --cq N            override the quality level (cq/crf)
      --mp4             write MP4 instead of MKV
      --verify          score the result against the source with VMAF
  -n, --dry-run         print the ffmpeg command and exit
  -o, --output FILE     output path
  -h, --help            this text

Quality ladder:
                  hevc_nvenc   libx265        libsvtav1
  compression     cq 29        crf 26 (slow)  crf 34 (preset 6)
  quality         cq 24        crf 20 (slow)  crf 28 (preset 5)
EOF
}

die () { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
info () { printf '\033[1;36m%s\033[0m\n' "$*"; }

# ------------------------------------------------------------------- arguments
while (( $# )); do
  case "$1" in
    -m|--mode)          mode="${2:-}"; shift 2 ;;
    -c|--cpu)           useCPU=true; shift ;;
    --av1)              useAV1=true; useCPU=true; shift ;;
    -s|--original-size) originalSize=true; shift ;;
    --max-width)        maxWidth="${2:-}"; shift 2 ;;
    --fps)              targetFPS="${2:-}"; shift 2 ;;
    -q|--cq)            cqOverride="${2:-}"; shift 2 ;;
    --mp4)              container='mp4'; shift ;;
    --verify)           verify=true; shift ;;
    -n|--dry-run)       dryRun=true; shift ;;
    -o|--output)        outFile="${2:-}"; shift 2 ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 die "unknown option: $1" ;;
    *)                  [[ -n ${inFile:-} ]] && die "only one input file at a time"
                        inFile="$1"; shift ;;
  esac
done

[[ -n ${inFile:-} ]] || { usage; exit 2; }
[[ -f $inFile ]]     || die "not a file: $inFile"
[[ $mode == compression || $mode == quality ]] || die "mode must be compression or quality"
[[ -x $ffmpeg_bin ]] || die "ffmpeg not found at $ffmpeg_bin"

inFile=$(readlink -f -- "$inFile")
baseName=${inFile%.*}
[[ -n $outFile ]] || outFile="${baseName}_recode.${container}"

# ----------------------------------------------------------------------- probe
# cc_probe writes .probe.rc into the working directory, so run it somewhere
# disposable rather than littering wherever the user happens to be.
probeCmd=$(command -v cc_probe || echo "$scriptDir/cc_probe.sh")
[[ -x $probeCmd ]] || die "cc_probe not found (tried PATH and $scriptDir/cc_probe.sh)"

probeDir=$(mktemp -d)
trap 'rm -rf "$probeDir"' EXIT
( cd "$probeDir" && "$probeCmd" "$inFile" >/dev/null ) \
  || die "cc_probe failed on $inFile"
[[ -s $probeDir/.probe.rc ]] || die "cc_probe wrote no .probe.rc"

# shellcheck disable=SC1091
source "$probeDir/.probe.rc"

# Without this guard an unset vWidth becomes 0 and every downstream size test
# silently does the wrong thing.
[[ ${vWidth:-} =~ ^[0-9]+$ && ${vWidth:-0} -gt 0 ]] \
  || die "probe returned no usable video width for $inFile"
[[ -n ${vMap:-} ]] || die "probe found no video stream in $inFile"

srcPixFmt=$("$ffprobe_bin" -v error -select_streams v:0 \
              -show_entries stream=pix_fmt -of csv=p=0 "$inFile" 2>/dev/null)
srcIs10bit=false
[[ $srcPixFmt == *10* || $srcPixFmt == *12* ]] && srcIs10bit=true

# --------------------------------------------------------------- encoder choice
# These capture before grepping on purpose. Piping straight into `grep -q` makes
# grep exit on the first match, ffmpeg takes SIGPIPE, and under `pipefail` the
# whole probe reports failure -- which silently demoted every GPU encode to CPU.
encoderSupports () {  # encoder, pix_fmt
  local help
  help=$("$ffmpeg_bin" -hide_banner -h "encoder=$1" 2>/dev/null) || return 1
  grep -q "Supported pixel formats:.*$2" <<< "$help"
}
haveEncoder () {
  local list
  list=$("$ffmpeg_bin" -hide_banner -encoders 2>/dev/null) || return 1
  grep -qw -- "$1" <<< "$list"
}
haveFilter () {
  local list
  list=$("$ffmpeg_bin" -hide_banner -filters 2>/dev/null) || return 1
  grep -qw -- "$1" <<< "$list"
}

hwaccel_args=()
vOpts=()

if $useAV1; then
  haveEncoder libsvtav1 || die "libsvtav1 not available; rebuild ffmpeg with --enable-libsvtav1"
  if [[ $mode == quality ]]; then svtPreset=5; defaultCQ=28; else svtPreset=6; defaultCQ=34; fi
  cq=${cqOverride:-$defaultCQ}
  vOpts=( -c:v libsvtav1 -preset "$svtPreset" -crf "$cq" )
  encName="libsvtav1 preset $svtPreset crf $cq"

elif $useCPU; then
  haveEncoder libx265 || die "libx265 not available"
  cq=${cqOverride:-$([[ $mode == quality ]] && echo 20 || echo 26)}
  vOpts=( -c:v libx265 -preset slow -crf "$cq" )
  encName="libx265 slow crf $cq"

else
  if ! haveEncoder hevc_nvenc; then
    info "hevc_nvenc unavailable, falling back to libx265"
    useCPU=true
    cq=${cqOverride:-$([[ $mode == quality ]] && echo 20 || echo 26)}
    vOpts=( -c:v libx265 -preset slow -crf "$cq" )
    encName="libx265 slow crf $cq (fallback)"
  else
    cq=${cqOverride:-$([[ $mode == quality ]] && echo 24 || echo 29)}
    # -b:v 0 keeps the default bitrate out of the CQ calculation, and -rc vbr
    # pins rate control instead of inheriting it from a preset. -highbitdepth
    # measured smaller *and* higher SSIM than 8-bit at identical speed.
    vOpts=( -c:v hevc_nvenc -preset p6 -tune hq -rc vbr -b:v 0 -cq "$cq"
            -rc-lookahead 32 -spatial-aq 1 -aq-strength 8 -temporal-aq 1
            -b_ref_mode middle -multipass fullres -highbitdepth 1 )
    encName="hevc_nvenc p6 cq $cq"
    # Let ffmpeg pick NVDEC per stream; it falls back to software on its own for
    # codecs this GPU cannot decode. Naming a *_cuvid decoder instead would
    # override the hwaccel and hard-fail on unsupported input.
    hwaccel_args=( -hwaccel cuda )
  fi
fi

# ------------------------------------------------------------------ pixel format
# NVENC takes 8-bit input and encodes 10-bit via -highbitdepth. The CPU encoders
# want to be handed 10-bit directly, but only if this build can do it -- the old
# local x265 was 8-bit only and silently ignored the request.
if [[ ${vOpts[1]} == hevc_nvenc ]]; then
  $srcIs10bit && pixFmt=p010le || pixFmt=yuv420p
else
  if $srcIs10bit || encoderSupports "${vOpts[1]}" yuv420p10le; then
    encoderSupports "${vOpts[1]}" yuv420p10le && pixFmt=yuv420p10le || pixFmt=yuv420p
  else
    pixFmt=yuv420p
  fi
fi

# ---------------------------------------------------------------- video filters
vFilterParts=()

if ! $originalSize && (( vWidth > maxWidth )); then
  vFilterParts+=( "scale=${maxWidth}:-2" )
fi
# Deliberately no upscale branch: enlarging SD costs bytes and adds nothing.

if [[ $targetFPS != none ]]; then
  targetDec=$(awk "BEGIN{printf \"%.4f\", $targetFPS}")
  if [[ ${vFPS:-0} != 0 ]] && awk "BEGIN{exit !(${vFPS} > ${targetDec})}"; then
    vFilterParts+=( "fps=fps=${targetFPS}" )
  fi
fi

# Clamp last, so a Main10 source cannot abort the encoder before frame one.
vFilterParts+=( "format=${pixFmt}" )

vFilter=$(IFS=,; echo "${vFilterParts[*]}")

# ---------------------------------------------------------------------- audio
aOpts=()
if [[ -n ${aMap:-} ]]; then
  aacEncoder=libfdk_aac
  haveEncoder libfdk_aac || aacEncoder=aac
  # Pass through anything already small and stereo rather than generation-lossing
  # it. Matroska often stores no audio bit_rate at all, so an unknown rate on an
  # already-stereo AAC/Opus track still copies -- re-encoding it could only lose.
  aRate=${aBitrate:-0}
  [[ $aRate =~ ^[0-9]+$ ]] || aRate=0
  if [[ ${aCodec:-} =~ ^(aac|opus)$ ]] \
     && [[ ${aChannels:-9} -le 2 ]] \
     && (( aRate <= 200 )); then
    aOpts=( -c:a copy )
    (( aRate > 0 )) && audName="copy (${aCodec} ${aRate}k)" \
                    || audName="copy (${aCodec}, rate not reported)"
  else
    aOpts=( -c:a "$aacEncoder" -b:a "$aBitrateTarget" -ac 2 )
    audName="$aacEncoder $aBitrateTarget stereo"
  fi
else
  audName="none"
fi

# ------------------------------------------------------------------- subtitles
sOpts=()
if [[ -n ${sMap:-} ]]; then
  if [[ $container == mp4 ]]; then
    sOpts=( -c:s mov_text )
  else
    sOpts=( -c:s copy )
  fi
fi

# --------------------------------------------------------------- assemble command
cmd=( "$ffmpeg_bin" -hide_banner -y "${hwaccel_args[@]}" -i "$inFile" )
# shellcheck disable=SC2206  # intentional split: cc_probe emits "-map 0:0" strings
cmd+=( ${vMap} ${aMap:-} ${sMap:-} )
cmd+=( -map_metadata 0 -map_chapters 0 )
cmd+=( "${vOpts[@]}" -vf "$vFilter" )
cmd+=( "${aOpts[@]}" "${sOpts[@]}" )
[[ $container == mp4 ]] && cmd+=( -movflags +faststart )
cmd+=( "$outFile" )

info "Input   : $inFile"
# shellcheck disable=SC2154  # vCodec sourced from .probe.rc
info "          ${vCodec} ${vWidth}x${vHeight:-?} @ ${vFPS:-?}fps ${srcPixFmt}, ${fSize:-?}"
info "Video   : $encName"
info "Filter  : $vFilter"
info "Audio   : $audName"
info "Output  : $outFile"
echo

if $dryRun; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

"${cmd[@]}"
STATUS=$?

if (( STATUS != 0 )); then
  die "encoding failed with exit code $STATUS"
fi

# ------------------------------------------------------------------- reporting
inBytes=$(stat -c%s "$inFile")
outBytes=$(stat -c%s "$outFile")
echo
info "Encoding completed"
printf '  Original : %s\n' "$(numfmt --to=iec --suffix=B "$inBytes")"
printf '  New      : %s (%s%% of original)\n' \
  "$(numfmt --to=iec --suffix=B "$outBytes")" \
  "$(awk "BEGIN{printf \"%.1f\", ($outBytes/$inBytes)*100}")"

if $verify; then
  if ! haveFilter libvmaf; then
    info "  VMAF     : unavailable (rebuild ffmpeg with --enable-libvmaf)"
  else
    info "  Scoring with VMAF..."
    # The reference gets the SAME scale/fps chain the encode used. Without that,
    # a 23.976fps output is compared frame-for-frame against a 30fps source, the
    # two drift apart within the first second, and the score is meaningless
    # (measured 25.6 instead of ~97). Matching the chain first also makes the
    # score mean "how well did the encoder do", not "how much did downscaling and
    # the frame rate cap change the picture" -- those were asked for.
    # settb/setpts then make frame-index alignment valid, since both now match.
    score=$("$ffmpeg_bin" -hide_banner -loglevel info -i "$outFile" -i "$inFile" \
      -lavfi "[0:v]settb=AVTB,setpts=N,scale=1920:-2:flags=bicubic[dist];\
[1:v]${vFilter},settb=AVTB,setpts=N,scale=1920:-2:flags=bicubic[ref];\
[dist][ref]libvmaf" \
      -f null - 2>&1 | grep -oP 'VMAF score:\s*\K[0-9.]+' | tail -1)
    printf '  VMAF     : %s\n' "${score:-could not be computed}"
  fi
fi

# vim: set syntax=bash:
# vim: set filetype=sh:
# vim: set shiftwidth=2:
# vim: set tabstop=2:
# vim: set expandtab:
