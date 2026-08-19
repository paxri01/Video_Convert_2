#!/bin/bash

# This script will search for video files in various directories as specified by the command line arguments.
# The script builds an array of incoming files and then probes the file and will convert it to the specified
# format base on the command line arguments.

# Expected incoming directory structure:
# renamed/                            <-- This is the search directory.
# ├── features
# ├── mtv
# ├── restricted
# ├── series                          <-- This is the search directory with subdirectories for each series.
# │   └── Series 1
# |       └── S04
# │   └── Series 2
# |       └── S08
# │   └── Series 3
# |       └── S02
# │   └── Series 4
# |       └── S01
# │   └── Series 5
# |       └── S07
# │   └── Series 5
# |       └── S01                    <-- This is where the series video files are located.
# |       └── S02
# |       └── S03
# ├── other
# ├── video

# The output directory structure will be duplicated from the search directory structure.
# Starting at $videoDir base.

# Program settings
  ffmpeg_bin='/usr/local/bin/ffmpeg'
  #ffmpeg_bin='/usr/bin/ffmpeg'
  #sample_range="-t 10:00"
  sample_range="-ss 01:00 -t 06:00"
  baseDir='/data2/usenet'
  searchDir="$baseDir/renamed"
  workDir="$baseDir/tmp"
  logDir='/var/log/convert'
  logFile="$logDir/ccvc.log"
  traceLog="$logDir/ccvc_trace_$(date +%F).log"
  doneDir="$baseDir/done"
  videoDir="/video"
  tempDir="/video/temp"
  user="serviio"
  group="video"
  # Concurrent encodes. With NVDEC handling decode a single job uses roughly
  # 570% CPU, so 2 fits comfortably in 16 cores while keeping each job's
  # single-threaded loudnorm filter on its own core. Override with -j.
  maxJobs=2

  # Default video parameters
  audio_codec='libfdk_aac'
  video_codec='libx264'
  hq='false'
  lq='false'
  outBase="$videoDir"

  usage()
  {
    cat << EOM
  NAME
      $0 - video converter

  SYNOPSIS
      $0 [OPTION]

  DESCRIPTION
      Re-encodes video files to sane/portable parameters.
      NVIDIA GPU is used automatically when detected; software fallback otherwise.

      -h, --help
          This documentation.

      -j, --jobs <n>
          Number of encodes to run concurrently (default 2). Use 1 for the
          previous serial behavior with live per-file progress output.

      --hq
          Will re-encode video with high quality settings.

      --lq
          Will re-encode video with low quality settings.

      --no-gpu
          Disable hardware acceleration even if an NVIDIA GPU is detected.

      -m, --movie
          Will look for feature length movies in configured directory.

      --mv
          Will look for music videos in configured directory.

      -o, --other
          Will look for other type video files in configured directory.

      -s, --series
          Will look for series shows in configured directory.

      -v, --video
          Will look for video files in configured directory.

      -x, --restrict
          Will look for restricted videos in configured directory.

      -z
          Will look for restricted plex videos in zFeatures directory.

      -zs
          Will look for series shows in zSeries directory; output goes
          to /video/zSeries.

  AUTHOR
      Written by Richard L. Paxton.

  EXAMPLES
      The following would search for movie files and re-encode them at high quality.
      $0 -m --hq

      The following would search for series files with hardware acceleration disabled.
      $0 -s --no-gpu

EOM
    exit 1
  }

# Configuration function to set encoding parameters
  setEncodeParams() {
    local type="$1"
    case "$type" in
      "movie")
        aRemix='true'
        inDir="$searchDir/features"
        sample_range='-t 15:00'
        target_FPS='24000/1001'
        target_QF='.1'
        target_aBitrate='160k'
        target_sampleRate='48k'
        vPreset='medium'
        vResize='true'
        vTune='film'
        ;;
      "mv")
        aRemix='true'
        audioChannels='2'
        inDir="$searchDir/mtv"
        target_FPS='30'
        target_QF='.2'
        target_aBitrate='192k'
        target_sampleRate='48k'
        vPreset='slow'
        vResize='true'
        vTune='film'
        ;;
      "other")
        aRemix='true'
        inDir="$searchDir/other"
        target_FPS='24000/1001'
        target_QF='.1'
        target_aBitrate='160k'
        target_sampleRate='48k'
        vPreset='slow'
        vResize='true'
        vTune='film'
        ;;
      "series")
        aRemix='true'
        audioChannels='2'
        inDir="$searchDir/series"
        target_FPS='24000/1001'
        target_QF='.08'
        target_aBitrate='128k'
        target_sampleRate='48k'
        vPreset='fast'
        vResize='true'
        vTune='film'
        ;;
      "video")
        aRemix='true'
        inDir="$searchDir/video"
        target_FPS='30'
        target_QF='.2'
        target_aBitrate='192k'
        target_sampleRate='48k'
        vPreset='slow'
        vResize='false'
        ;;
      "restricted")
        aRemix='true'
        audioChannels='2'
        inDir="$searchDir/restricted"
        target_FPS='25'
        target_QF='.08'
        target_aBitrate='92k'
        vPreset='fast'
        vResize='true'
        vTune='film'
        ;;
      "zfeatures")
        aRemix='true'
        audioChannels='2'
        inDir="$searchDir/zFeatures"
        target_FPS='25'
        target_QF='.08'
        target_aBitrate='92k'
        vPreset='fast'
        vResize='true'
        vTune='film'
        ;;
      "zseries")
        aRemix='true'
        audioChannels='2'
        inDir="$searchDir/zSeries"
        target_FPS='24000/1001'
        target_QF='.08'
        target_aBitrate='128k'
        target_sampleRate='48k'
        vPreset='fast'
        vResize='true'
        vTune='film'
        ;;
    esac
  }

# Process command line arguments
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      -h | --help) #Display help
        usage
        ;;
      --hq) #Set high quality override
        hq='true'
        sample_range=''  # sample the entire video file
        vResize='false'
        shift
        ;;
      --lq)  #Set low quality override
        lq='true'
        audioChannels='2'
        shift
        ;;
      --no-gpu) #Disable hardware acceleration
        GPU_AVAILABLE=false
        shift
        ;;
      -j | --jobs) #Number of concurrent encodes
        if [[ ! $2 =~ ^[1-9][0-9]*$ ]]; then
          echo -e "${C1}ERROR: 11 - --jobs requires a positive integer${C0}"
          usage
        fi
        maxJobs=$2
        shift 2
        ;;
      -m | --movie) #Process movies
        setEncodeParams "movie"
        shift
        ;;
      --mv) #music video files
        setEncodeParams "mv"
        shift
        ;;
      -o | --other) #Process other videos
        setEncodeParams "other"
        shift
        ;;
      -s | --series) #tv series encodes
        setEncodeParams "series"
        shift
        ;;
      -v | --video) #video files
        setEncodeParams "video"
        shift
        ;;
      -x | --restricted) #restricted videos
        setEncodeParams "restricted"
        shift
        ;;
      -z ) #restricted plex videos
        setEncodeParams "zfeatures"
        shift
        ;;
      -zs) #zseries encodes (output stays under searchDir)
        setEncodeParams "zseries"
        shift
        ;;

      *)  #Unknown option
        echo -e "${C1}ERROR: 10 - Unknown option '$1'${C0}"
        usage
        ;;
    esac
  done


# Set video overrides if passed
  if [[ $hq == 'true' ]]; then
    aRemix='false'
    target_FPS='60'
    target_QF='.2'
    target_aBitrate='192k'
    target_sampleRate='48k'
    vPreset='slow'
    vResize='false'
    vTune='film'
  elif [[ $lq == 'true' ]]; then
    aRemix='true'
    target_FPS='23.976'
    target_QF='.08'
    target_aBitrate='128k'
    target_sampleRate='48k'
    vPreset='fast'
    vResize='true'
    vTune='film'
  fi

# Misc settings
  pad=$(printf '%0.1s' "."{1..100})
  padlength=100
  interval=.5
  rPID=""
  trap 'deadJim' 1 2 3 15

# Add some colors
  C0='\033[0;00m'      # Reset
  C1='\033[38;5;160m'  # ReD
  C2='\033[38;5;040m'  # Green
  C3='\033[38;5;184m'  # Yellow
  C4='\033[38;5;063m'  # Blue
  C5='\033[38;5;165m'  # Purple
  #C6='\033[38;5;234m'  # Dark
  C7='\033[38;5;254m'  # White
  C8='\033[38;5;243m'  # Grey

# Hardware acceleration detection (after colors so status message is colored)
  if [[ ${GPU_AVAILABLE+x} != x ]]; then
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
      GPU_AVAILABLE=true
    else
      GPU_AVAILABLE=false
    fi
  fi

  hwaccel_args=''
  if [[ $GPU_AVAILABLE == true ]]; then
    if ! $ffmpeg_bin -encoders 2>/dev/null | grep -q 'h264_nvenc'; then
      echo -e "${C3}WARNING: NVIDIA GPU detected but h264_nvenc not available, falling back to software encoding${C0}"
      GPU_AVAILABLE=false
    else
      video_codec='h264_nvenc'
      # Decode on NVDEC in addition to encoding on NVENC. Decoded frames are
      # downloaded to system memory, so the CPU filter chain (scale/fps/format)
      # is unaffected. ffmpeg falls back to software decode per-stream if the
      # source codec is not NVDEC-supported.
      if $ffmpeg_bin -hwaccels 2>/dev/null | grep -qw 'cuda'; then
        hwaccel_args='-hwaccel cuda'
      fi
    fi
  fi

# Define Global variables
declare -a fullName fileName extension baseName baseDir outDir
declare vOpts vFilter aOpts aFilter sOpts outFile metaFile hwaccel_args

## Defined Functions
  logIt ()
  {
    echo "$(date '+%b %d %H:%M:%S') $1" >> "$logFile"
    return 0
  }

  errorExit ()
  {
    local msg="$1"
    local code="${2:-1}"
    echo -e "${C1}ERROR: $msg${C0}" >&2
    logIt "ERROR: $msg"
    exit "$code"
  }

  deadJim ()
  {
    # Display message and reset cursor on trap
    kill -9 "$rPID" > /dev/null 2>&1
    wait "$rPID" 2>/dev/null
    echo ""
    Text1="Abort detected, stopping now"
    # shellcheck disable=SC2059
    printf "  ${C1}${Text1}${C0}"
    printf '%*.*s' 0 $((padlength - ${#Text1} - 6 )) "$pad"
    echo -e "\b\b\c"
    echo -e "[${C5}KILLED${C0}]"
    tput cnorm
    exit 1
  }

  traceIt ()
  {
    # $1 = $LINENO, $2 = function, $3 = status, $4 = description
    echo "$(date '+%b %d %H:%M:%S') [$(printf "%.3d" "$1")] $2: [$3] $4" >> "$traceLog"
    return 0
  }

  displayIt ()
  {
    local Text1="$1"
    local Text2="${2:-}"
    local padding

    if (( $# > 1 )); then
      local max_t2=$(( padlength - ${#Text1} - 7 ))
      if (( ${#Text2} > max_t2 )); then
        Text2="${Text2:0:$(( max_t2 - 3 ))}..."
      fi
      printf "  %b" "${C8}${Text1}${C4}${Text2}${C0}"
      padding=$(( padlength - ${#Text1} - ${#Text2} - 6 ))
    else
      printf "  %b" "${C8}${Text1}${C0}"
      padding=$(( padlength - ${#Text1} - 6 ))
    fi
    (( padding < 1 )) && padding=1
    printf '%*.*s' 0 $padding "$pad"

    rotate &
    rPID=$!
    return 0
  }

  rotate ()
  {

    while :
    do
      tput civis
      ((z++))
      #shellcheck disable=SC1003
      case $z in
        "1") echo -e "-\b\c"
          sleep $interval
          ;;
        "2") echo -e '\\'"\b\c"
          sleep $interval
          ;;
        "3") echo -e "|\b\c"
          sleep $interval
          ;;
        "4") echo -e "/\b\c"
          sleep $interval
          ;;
        *) z=0 ;;
      esac
    done
  }

  killWait ()
  {
    FLAG=$1
    kill -9 "$rPID"
    wait "$rPID" 2>/dev/null
    echo -e "\b\b\c"
    tput cnorm

    case $FLAG in
      "0") echo -e "[${C2}  OK  ${C0}]"
        ;;
      "1") echo -e "[${C1}ERROR!${C0}]"
        ;;
      "2") echo -e "[${C3} WARN ${C0}]"
        ;;
      *) echo -e "[${C5}UNKWN!${C0}]"
        ;;
    esac
    return 0
  }

  getFiles ()
  {
    ## Find following file types within inDir and process directly
    ## Filter any with .zzz extension.
    local i=0 fileNo tempFile
    mapfile -t file_list < <(find "$inDir" -type f -iregex '.*.\(avi\|mgp\|mp4\|m4v\|wmv\|avi\|mpg\|mov\|mkv\|flv\|webm\|ts\|f4v\)' -not -path '*.zzz*' -print)

    # Process each file and populate arrays
    for LINE in "${file_list[@]}"; do
      fileNo=$((i+1))
      fullName[i]="$LINE"
      fileName[i]="${fullName[$i]##*/}"
      # Strip search directory from base directory.
      local fullDir="${fullName[$i]%/*}"
      baseDir[i]="${fullDir#"$searchDir/"}"
      tempFile="${fileName[$i]}"
      extension[i]="${tempFile##*.}"
      baseName[i]="${tempFile%.*}"
      outDir[i]="${outBase}/${baseDir[$i]}"

      traceIt $LINENO getFiles " info " "== Processing file number: [$(printf '%.3d' $fileNo)] =="
      traceIt $LINENO getFiles " info " " fullName: ${fullName[$i]}"
      traceIt $LINENO getFiles " info " "directory: ${baseDir[$i]}"
      traceIt $LINENO getFiles " info " " fileName: ${fileName[$i]}"
      traceIt $LINENO getFiles " info " " baseName: ${baseName[$i]}"
      traceIt $LINENO getFiles " info " "extension: ${extension[$i]}"
      traceIt $LINENO getFiles " info " "   outDir: ${outDir[$i]}"
      ((i++))
    done
    return 0
  }

  getMeta ()
  {
    # Metadata
    inFile=$1
    # Extract title and date using bash parameter expansion
    local pattern='^(.+[[:space:]])\(([^)]+)\)'
    if [[ "$inFile" =~ $pattern ]]; then
      fTitle="${BASH_REMATCH[1]}"
      fDate="${BASH_REMATCH[2]%% *}"  # Get first word of date
    else
      fTitle="$inFile"
      fDate=""
    fi
    fDate=${fDate:-$(date +%F)}
    metaFile="${workDir}/${inFile}.meta"
    unset meta_title meta_data meta_synopsis

    meta_title=${meta_title:-$fTitle}
    meta_date=${meta_date:-$fDate}
    meta_synopsis=${meta_synopsis:-'No info'}
    meta_composer="the Gh0st"
    meta_comment="$ffmpeg_string"

    echo ";FFMETADATA1" > "$metaFile"
    metaData[0]="title=$meta_title"
    metaData[1]="date=$meta_date"
    metaData[2]="synopsis=$meta_synopsis"
    metaData[3]="comment=$meta_comment"
    metaData[4]="composer=$meta_composer"

    j=0
    while (( j < ${#metaData[*]} ))
    do
      echo "${metaData[$j]}" >> "$metaFile"
      j=$((j+1))
    done

    return 0
  }

  normalizeIt ()
  {
    inFile=$1

    if ! command -v cc_norm >/dev/null 2>&1; then
      errorExit "cc_norm not found in \$PATH"
    fi

    normalize=$(cc_norm "$inFile" $ffmpeg_bin "$sample_range")
    STATUS=$?
    if (( STATUS > 0 )); then
      echo "$normalize"
      normalize=''
    fi
    traceIt $LINENO normalIt " info " "normalize=$normalize"

    return 0
  }

  probeIt ()
  {
    inFile="$1"

    if ! command -v cc_probe >/dev/null 2>&1; then
      errorExit "cc_probe not found in \$PATH"
    fi

    cc_probe "$inFile"
    # shellcheck disable=SC1091

    if [[ -f .probe.rc ]]; then
      source .probe.rc
    else
      errorExit "cc_probe failed to generate .probe.rc file" 2
    fi
    # shellcheck disable=SC2154
    { echo "> fName=$fName"
    echo "> fSize=$fSize"
    echo "> duration=$duration"
    echo "> vStream=$mainVideo"
    echo "> vWidth=$vWidth"
    echo "> vHeight=$vHeight"
    echo "> vBitrate=$vBitrate"
    echo "> vFPS=$vFPS"
    echo "> vLanguage=$vLanguage"
    echo "> vMap=$vMap"
    echo "> aStream=$mainAudio"
    echo "> aBitrate=$aBitrate"
    echo "> aSample=$aSampleRate"
    echo "> aChannels=$aChannels"
    echo "> aLanguage=$aLanguage"
    echo "> aMap=$aMap"
    echo "> sMap=$sMap"
    } >> "$traceLog"

    rm .probe.rc
    return 0
  }

  buildVideoFilter ()
  {
    # shellcheck disable=SC2154 # vMap sourced from probeIt()
    vFilter="$vMap "
    vFilter+='-vf '

    # Check if video needs to be resized.
    if [[ $vResize != 'true' ]]; then
      traceIt $LINENO buildVideoFilter " info " "Skipping video resize due to override."
    else
      # Resize video based on video width (vWidth sourced from probeIt)
      # shellcheck disable=SC2154  # vWidth sourced from probeIt()
      if (( vWidth > 1280 )); then
        vFilter+="scale=1280:-2,"
        scale=$(awk "BEGIN {printf \"%.6f\", 1280/$vWidth}")
      elif (( vWidth < 720  )); then
        vFilter+="scale=720:-2,"
        scale=$(awk "BEGIN {printf \"%.6f\", 720/$vWidth}")
      else
        scale=1
      fi
    fi

    # Check measured video FPS to targetFPS.
    #shellcheck disable=SC2154  # vFPS sourced from probeIt()
    if [[ $(awk "BEGIN {print ($vFPS >= $target_FPS)}") == "1" ]]; then
      FPS=$target_FPS
    else
      FPS=$vFPS
    fi
    vFilter+="fps=fps=$FPS"
    # This can be used to blur logo maps.
    if [[ -e $inDir/${baseName[$l]}.png ]]; then
      vFilter+=",removelogo=\"$inDir/${baseName[$l]}.png\""
    fi
    # Force 8-bit output. h264_nvenc cannot encode 10-bit (e.g. UHD BluRay
    # HEVC Main 10) sources and aborts before the first frame otherwise.
    vFilter+=",format=yuv420p"
    traceIt $LINENO buildVideoFilter " info " "vFilter: $vFilter"
  }

  buildVideoOpts ()
  {
    vOpts="-c:v $video_codec "

    # Calculate video bitrate
    #shellcheck disable=SC2154  # vHeight sourced from probeIt()
    local _vSize _hSize
    _vSize=$(awk "BEGIN {printf \"%.0f\", $vHeight*$scale}")
    _hSize=$(awk "BEGIN {printf \"%.0f\", $vWidth*$scale}")
    target_vBitrate=$(awk "BEGIN {printf \"%.0f\", ($target_QF*$_hSize*$_vSize*$FPS)/1000}")
    traceIt $LINENO buildVideoOpts " info " "target_vBitrate=$target_vBitrate"

    vOpts+="-b:v ${target_vBitrate}k "

    if [[ $video_codec == *"nvenc"* ]]; then
      # NVENC encoder options
      vOpts+="-preset $vPreset "
      vOpts+="-rc vbr "
      vOpts+="-cq 23 "
      vOpts+="-bufsize $((target_vBitrate * 2))k "
      vOpts+="-maxrate $((target_vBitrate + target_vBitrate/2))k "
      vOpts+="-multipass 2"
    else
      # CPU encoder options
      vOpts+="-preset $vPreset "
      vOpts+="-tune $vTune"
    fi
    traceIt $LINENO buildVideoOpts " info " "vOpts: $vOpts"
  }

  buildAudioOpts ()
  {
    #shellcheck disable=SC2154  # aMap sourced from probeIt()
    if [[ -n $aMap ]]; then
      aFilter="$aMap "
      if [[ -n $normalize ]]; then
        aFilter+="$normalize"
      fi

      # Build audio codec string
      aOpts="-c:a $audio_codec "
      aOpts+="-b:a $target_aBitrate "
      if [[ $aRemix != 'true' ]]; then
        aOpts+="-ac 2 "
      else
        #shellcheck disable=SC2154  # aChannels sourced from probeIt()
        aOpts+="-ac ${audioChannels:-$aChannels} "
      fi
      aOpts+="-ar ${target_sampleRate:-48k}"
    else
      aOpts='-an'
    fi
    traceIt $LINENO buildAudioOpts " info " "aOpts: $aOpts"
  }

  buildSubtitleOpts ()
  {
    if [[ -n $sMap ]]; then
      sOpts="-c:s mov_text "
      sOpts+="-metadata:s:s:0 "
      sOpts+="language=eng "
      sOpts+="$sMap"
    else
      sOpts="-sn"
    fi
  }

  setOpts ()
  {
    buildVideoFilter
    buildVideoOpts
    buildAudioOpts
    buildSubtitleOpts
    return 0
  }

  encodeIt ()
  {
    inFile=$1

    if [[ ! -d "${outDir[$l]}" && ! -h "${outDir[$l]}" ]]; then
      mkdir -p "${outDir[$l]}"
      check=$?
      if [[ $check -ne 0 ]]; then
        logIt "ERROR: Could not create directory ${outDir[$l]}"
        traceIt $LINENO encodeIt "ERROR!" "Could not create directory ${outDir[$l]}"
        killWait 1 "Could not create directory ${outDir[$l]}"
        exit $check
      fi
      chown $user:$group "${outDir[$l]}" 2>/dev/null
      chmod 0775 "${outDir[$l]}" 2>/dev/null
    fi
    if [[ $hq != 1 ]]; then
      outFile="${outDir[$l]}/${baseName[$l]}.mp4"
    else
      outFile="${outDir[$l]}/${baseName[$l]}-∞.mp4"
    fi

    ffmpeg_string="${ffmpeg_bin} "
    ffmpeg_string+="-hide_banner -y "
    ffmpeg_string+="-loglevel quiet -stats "
    [[ -n $hwaccel_args ]] && ffmpeg_string+="$hwaccel_args "
    ffmpeg_string+="-i \"$inFile\" "
    ffmpeg_string+="-i \"$metaFile\" "
    ffmpeg_string+="-map_metadata 1 "
    ffmpeg_string+="$vOpts "
    ffmpeg_string+="$vFilter "
    ffmpeg_string+="$aOpts "
    ffmpeg_string+="$aFilter "
    ffmpeg_string+="$sOpts "
    # Unique per job: a fixed name here is shared by concurrent encodes, and the
    # mv below would move another job's partial file to this job's destination.
    tempOut="$tempDir/converting.$$.$l.mp4"

    traceIt $LINENO encodeIt "  CMD  " "> $ffmpeg_string $outFile"

    jobLog=''
    if (( maxJobs > 1 )); then
      # Concurrent jobs would interleave ffmpeg's -stats output on the terminal,
      # so each job's progress is captured to its own log instead.
      jobLog="$logDir/encode.$$.$l.log"
      bash -c "$ffmpeg_string $tempOut" > "$jobLog" 2>&1
      STATUS=$?
    else
      echo -e "                                      total time=${C3}$duration${C0}"
      bash -c "$ffmpeg_string $tempOut"
      STATUS=$?
    fi

    if (( STATUS > 0 )); then
      logIt "Re-encoding of $inFile failed!"
      traceIt $LINENO encodeIt "ERROR!" "STATUS=$STATUS, ffmpeg encode failed."
      echo -e "> ${C1}ERROR (${baseName[$l]}): Run the following to see details why:\n${ffmpeg_string//-loglevel quiet -stats /} $tempOut${C0}\n"
      [[ -n $jobLog ]] && echo -e "> ${C1}ffmpeg output: $jobLog${C0}"
      rm -f "$tempOut"
    else
      mv -f "$tempOut" "$outFile"
      # Concurrent jobs cannot share the terminal for live progress, so recover
      # ffmpeg's final stats line from the job log and report it on completion.
      # -stats separates updates with \r, hence the translation.
      encStats=''
      if [[ -n $jobLog && -f $jobLog ]]; then
        encStats=$(tr '\r' '\n' < "$jobLog" | grep -E '^frame=' | tail -1)
        rm -f "$jobLog"
      fi
      # Get file sizes efficiently using stat
      origSize=$(stat -c%s "$inFile")
      newSize=$(stat -c%s "$outFile")

      # Convert to human readable format using bash
      origHuman=$(numfmt --to=iec-i --suffix=B "$origSize" 2>/dev/null || echo "${origSize}B")
      newHuman=$(numfmt --to=iec-i --suffix=B "$newSize" 2>/dev/null || echo "${newSize}B")
      diff=$(awk "BEGIN {printf \"%.2f\", (($newSize - $origSize)/$origSize)*100}")
      if (( newSize < origSize )); then
        # File decreased - show positive percentage
        decrease=$(awk "BEGIN {printf \"%.2f\", (($origSize - $newSize)/$origSize)*100}")
        sizeLine="Orig Size: $origHuman // New Size: $newHuman // ${C2}File decreased by ${decrease}%${C0}"
      else
        sizeLine="Orig Size: $origHuman // New Size: $newHuman // ${C1}File increased by ${diff}%${C0}"
      fi

      # Assembled and emitted as one write so that concurrent jobs cannot
      # interleave their report lines with each other.
      report="---------------------------"$'\n'
      report+="${C5}${baseName[$l]}${C0}"$'\n'
      [[ -n $encStats ]] && report+="${C8}total time=${duration} // ${encStats}${C0}"$'\n'
      report+="${sizeLine}"$'\n'
      report+="---------------------------"
      echo -e "$report" | tee -a "$logFile"

      # Cleanup temp files and variables
      rm "$metaFile" >/dev/null 2>&1
      unset sMap aMap vMap

      {
        mkdir -p "$doneDir/${baseDir[$l]}"
        chgrp -R admins "$doneDir/${baseDir[$l]}" 2>/dev/null
        mv "${fullName[$l]}" "$doneDir/${baseDir[$l]}/"
      } >> "$traceLog" 2>&1

      logIt "outFile = $outFile"
      chown $user:$group "$outFile" 2>/dev/null
      chmod 0664 "$outFile" 2>/dev/null
    fi

    # Logged here rather than in the main loop so the markers stay with the job
    # when encodes run concurrently.
    logIt "------------------------------------------------------------------"
    logIt "End of ${baseName[$l]}"
    logIt "^----------------------------------------------------------------^"
    traceIt $LINENO encodeIt " info " "END OF JOB: $((l+1))"
    if (( maxJobs > 1 )); then
      if (( STATUS > 0 )); then
        echo -e "  ${C1}Failed${C0}: ${baseName[$l]}"
      else
        echo -e "  ${C2}Done${C0}: ${baseName[$l]}"
      fi
    fi

    return $STATUS
  }




## MAIN
traceIt $LINENO " MAIN  " " info " "*** START OF NEW RUN ***"
echo -e "${C7}\nStarting run of ${C5}Video Converter 2${C0}"
if [[ $GPU_AVAILABLE == true ]]; then
  echo -e "  ${C2}Hardware acceleration enabled${C0} (${video_codec})"
else
  echo -e "  ${C8}Software encoding${C0} (${video_codec})"
fi
umask 002

displayIt "Collecting list of files to process"
getFiles
killWait $?

l=0
while (( l < ${#fullName[@]})) && (( l < 50 )); do
  traceIt $LINENO " MAIN  " " info " "START OF LOOP: $((l+1)) of ${#fullName[*]}"
  traceIt $LINENO " MAIN  " " info " "baseName=${baseName[$l]}"
  echo "" >> "$logFile"
  logIt "v----------------------------------------------------------------v"
  logIt "Start of ${baseName[$l]}"
  logIt "------------------------------------------------------------------"
  logIt "inFile=${fullName[$l]}"

  echo -e "\nFile $((l+1)) of ${#fullName[*]}"
  displayIt "Processing: " "${baseDir[$l]}/${baseName[$l]}"
  probeIt "${fullName[$l]}"
  killWait $?

  displayIt "Normalizing audio track"
  normalizeIt "${fullName[$l]}"
  killWait $?

  displayIt "Setting encode filters"
  setOpts
  killWait $?

  getMeta "${baseName[$l]}"

  if (( maxJobs > 1 )); then
    # Block until a slot frees up, then run this encode in the background. The
    # subshell gets a copy of the loop state, so the parent advancing $l cannot
    # disturb a job already running.
    while (( $(jobs -rp | wc -l) >= maxJobs )); do wait -n; done
    encodeIt "${fullName[$l]}" &
    echo -e "  ${C8}Started${C0} (${C3}$(( $(jobs -rp | wc -l) ))${C0}/${maxJobs} running)"
  else
    encodeIt "${fullName[$l]}"
    echo -e "  ${C2}Done${C0}"
  fi

  traceIt $LINENO " MAIN  " " info " "END OF LOOP: $((l+1))"
  echo "" >> "$traceLog"
  ((l++))
done

# Let any still-running background encodes finish before exiting.
if (( maxJobs > 1 )); then
  running=$(jobs -rp | wc -l)
  (( running > 0 )) && echo -e "\n${C7}Waiting on ${C3}${running}${C7} remaining encode(s)...${C0}"
  wait
fi
