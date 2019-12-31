#!/bin/bash
# set -x

# NOTE: Work-in-progress, still dinking with this....

# DESCRIPTION:  This script utilized ffmpeg to re-encode videos to the following:
#               Convert video to H.264, resize to minimum of 720 hSize and max of 1280 hSize,
#               with a target CRF of 20 and buffer size of 1500.  This means that the video
#               should play on all DLNA servers and TVs.
#               Convert audio to AAC, bitRate of 128Kbs.
#               If English subtitles are detected, it will also map those into output.

typeset streamMap baseName outFile encodeOpts videoOpts audioOpts vFrameRate fullName \
	fileName extension 
typeset -i i=0 j=0 l=0 Q=1

# Directory settings
baseDir='/data/usenet'
logDir='/var/log/convert'
searchDir="$baseDir/renamed"
workDir="$baseDir/tmp"
logFile="$logDir/ccvc.log"
traceLog="$logDir/ccvc_trace_$(date +%F).log"
doneDir="$baseDir/done"
videoDir="/video"

inFiles="$workDir/inFiles.lst"
tempDir="/video/temp"

# Audio sample range
#range="-ss 01:00 -t 06:00"
range="-t 10:00"

# Misc settings
pad=$(printf '%0.1s' "."{1..100})
padlength=100
interval=.5
rPID=""
trap 'deadJim' 1 2 3 15

# Add some colors
C1='\033[38;5;040m'  # Green
C2='\033[38;5;243m'  # Grey
C3='\033[38;5;254m'  # White
C4='\033[38;5;184m'  # Yellow
C5='\033[38;5;160m'  # Red
C6='\033[38;5;165m'  # Purple
C7='\033[38;5;063m'  # Blue
#C8='\033[38;5;234m'  # Dark
C0='\033[0;00m'      # Reset


logIt ()
{
  echo "$(date '+%b %d %H:%M:%S') $1" >> "$logFile"
  return 0
}

traceIt ()
{
  # $1 = $LINENO, $2 = function, $3 = status, $4 = description
  echo "$(date '+%b %d %H:%M:%S') [$(printf "%.3d" "$1")] $2: [$3] $4" >> "$traceLog"
  return 0
}

displayIt ()
{

  Text1="$1"
  Text2="$2"

  if (( $# > 1 )); then
    # shellcheck disable=SC2059
    printf "  ${C2}$Text1${C0} ${C7}$Text2${C0}"  
    printf '%*.*s' 0 $((padlength - ${#Text1} - ${#Text2} - 7 )) "$pad"
  else
    # shellcheck disable=SC2059
    printf "  ${C2}${Text1}${C0}"
    printf '%*.*s' 0 $((padlength - ${#Text1} - 6 )) "$pad"
  fi

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
    "0") echo -e "[${C1}  OK  ${C0}]"
      ;;
    "1") echo -e "[${C5}ERROR!${C0}]"
      ;;
    "2") echo -e "[${C4} WARN ${C0}]"
      ;;
    *) echo -e "[${C6}UNKWN!${C0}]"
      ;;
  esac
  return 0
}

deadJim ()
{
  # Display message and reset cursor on trap
  kill -9 "$rPID" > /dev/null 2>&1
  wait "$rPID" 2>/dev/null
  echo ""
  Text1="Abort detected, stopping now"
  # shellcheck disable=SC2059
  printf "  ${C5}${Text1}${C0}"
  printf '%*.*s' 0 $((padlength - ${#Text1} - 6 )) "$pad"
  echo -e "\b\b\c"
  echo -e "[${C6}KILLED${C0}]"
  tput cnorm
  exit 1
}

getFiles ()
{
  ## Find following file types within inDir.
  ## Filter any with .zzz extension.
  find "$inDir" -iregex '.*.\(mgp\|mp4\|m4v\|wmv\|avi\|mpg\|mov\|mkv\|flv\|webm\|ts\|f4v\)' \
    -fprintf "$inFiles" '%h/%f\n'
  sed -i '/\.zzz/d' "$inFiles"

  # The following if statements detect where the file is located and sets fType.
  i=0
  while read -r LINE; do
    fileNo=$((i+1))
    fullName[$i]="$LINE"
    fileName[$i]=$(basename "${fullName[$i]}")
    #inDir[$i]=$(dirname "${fullName[$i]}")
    # Strip search directory from base directory.
    baseDir[$i]=$(dirname "${fullName[$i]}" | sed -e "s@$searchDir/@@")
    tempFile="${fileName[$i]}"
    extension[$i]="${tempFile##*.}"
    baseName[$i]="${tempFile%.*}"
    #outDir[$i]="/nfs/video/${baseDir[$i]}"
    outDir[$i]="$videoDir/${baseDir[$i]}"

    traceIt $LINENO getFles " info " "== Processing file number: [$(printf '%.3d' $fileNo)] =="
    traceIt $LINENO getFles " info " " fullName: ${fullName[$i]}"
    traceIt $LINENO getFles " info " "directory: ${baseDir[$i]}"
    traceIt $LINENO getFles " info " " fileName: ${fileName[$i]}"
    traceIt $LINENO getFles " info " " baseName: ${baseName[$i]}"
    traceIt $LINENO getFles " info " "extension: ${extension[$i]}"
    traceIt $LINENO getFles " info " "   outDir: ${outDir[$i]}"
    ((i++))
  done < $inFiles
  rm $inFiles
  return 0
}

probeIt ()
{
  #set -x
  # Gather video information
  inFile="${fullName[$l]}"
  traceIt $LINENO probeIt " info " "inFile=\"$inFile\""

  probeFile="$workDir/${baseName[$l]}.probe"
  dataFile="$workDir/${baseName[$l]}.data"
  # In case of multiple runs.
  rm -f "$probeFile" "$dataFile" >/dev/null 2>&1
  ffprobe -show_entries streams -sexagesimal -of flat "$inFile" > "$probeFile" 2>&1
  sed -i 's/\"//g' "$probeFile"
  # To handle bitmap subs vs. text subtitles
  sed -i '/^programs\./d' "$probeFile"

  # Collect number of streams and type
  ## BAD_CODE ## stream=( $(grep '^streams\.' "$probeFile" | grep 'codec_type') )
  mapfile -t stream < <(grep -E '^streams\..*codec_type' "$probeFile")
  traceIt $LINENO probeIt " info " "stream=${stream[*]}"

  duration=$(grep 'Duration' "$probeFile" | awk -F',' '{print $1}' | awk '{print $2}')
  traceIt $LINENO probeIt " info " "duration=$duration"

  j=0; unset sample subMap vStream aStream sStream
  while (( j < ${#stream[*]} )); do
    # Assuming only 1 video stream.
    if grep -q 'video' <<< "${stream[$j]}" && [[ -z $vStream ]]; then
      vStream="0:${j}"
      traceIt $LINENO probeIt " info " "videoMap=0:$j"
      hSize=$(grep "\.${j}\.width" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "hSize=$hSize"
      vSize=$(grep "\.${j}\.height" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vSize=$vSize"
      videoSize="${hSize}x${vSize}"
      traceIt $LINENO probeIt " info " "videoSize=$videoSize"
      vBitRate=$(grep 'bitrate' "$probeFile" | awk -F: '{print $6}' | cut -c 2- | awk '{print $1}')
      traceIt $LINENO probeIt " info " "vBitRate=$vBitRate"
      vFrameRate=$(grep "stream\.${j}\.r_frame_rate=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vFrameRate=$vFrameRate"
      vLanguage=$(grep "stream\.${j}\..*language=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vLanguage=$vLanguage"
    # Assumed first audio stream is good
    elif grep -q 'audio' <<< "${stream[$j]}" && [[ -z $aStream ]]; then
      aStream="0:${j}"  ## Set to current audio stream.
      altStream="0:${j}" ## Set to last audio stream detected.
      sample=$(grep "stream\.${j}\.sample_rate=" "$probeFile" | awk -F'=' '{print $2}')
      aBitRate=$(grep -m 1 "stream\.${j}\.bit_rate=" "$probeFile" | awk -F'=' '{print $2}')
      aChannels=$(grep "stream\.${j}\.channels=" "$probeFile" | awk -F'=' '{print $2}')
      aLanguage=$(grep "stream\.${j}\..*language=" "$probeFile" | awk -F'=' '{print $2}')
      if [[ $aLanguage != 'en' && $aLanguage != 'eng' ]]; then
        traceIt $LINENO probeIt " info " "Audio stream $aStream is not tagged as english."
        unset aStream  ## Skip non-english audio.
        ((j++))
        continue
      fi
      traceIt $LINENO probeIt " info " "audioMap=0:$j"
      traceIt $LINENO probeIt " info " "sample=$sample"
      traceIt $LINENO probeIt " info " "aBitRate=$aBitRate"
      traceIt $LINENO probeIt " info " "aChannels=$aChannels"
      traceIt $LINENO probeIt " info " "aLanguage=$aLanguage"
    elif grep -q 'subtitle' <<< "${stream[$j]}"; then
      sCodec=$(grep "stream\.${j}\.codec_name=" "$probeFile" | awk -F'=' '{print $2}')
      sLanguage=$(grep "stream\.${j}\..*language=" "$probeFile" | awk -F'=' '{print $2}')
      # Cannot convert bitmap subtitles to text based within ffmpeg.
      if [[ $sLanguage =~ (en|eng) && $sCodec == 'subrip' ]]; then
        sStream="0:${j}"
        sMap="$sMap -map $sStream"
      fi
    fi
    ((j++))
  done
 
  #Use last found audio if no english stream detected. 
  aStream=${aStream:-$altStream}

  cat <<EOinfo >> "$dataFile"
videoSize=$videoSize
hSize=$hSize
vSize=$vSize
vBitRate=$vBitRate
vFrameRate=$vFrameRate
sample=$sample
aBitRate=$aBitRate
aChannels=$aChannels
aLanguage=$aLanguage
duration=$duration
streams:
  video=$vStream
  audio=$aStream
  subs=$sMap
EOinfo

  #set +x
  return 0
}

normalizeIt ()
{
  #set -x
  inFile="${fullName[$l]}"
  if [[ -z $aStream ]]; then
    aOpts=
    logIt "No audio to normalize, skipping."
    return 1
  fi

  traceIt $LINENO nrmlzIt " info " "Sample command:"
  cat << EOcmd >> "$traceLog"
> ffmpeg -hide_banner -y $range -i "$inFile" -map $aStream -vn -sn -filter:a loudnorm=print_format=json \
-f mp4 /dev/null 2>&1 | sed -n '/{/,/}/p' > "$tempDir/sample.json"
EOcmd

  # shellcheck disable=SC2086
  ffmpeg -hide_banner -y $range -i "$inFile" -vn -sn -filter:a loudnorm=print_format=json \
    -f mp4 /dev/null 2>&1 | sed -n '/{/,/}/p' > "$tempDir/sample.json"

  input_i=$(jq .input_i < $tempDir/sample.json | tr -d '"')
  input_tp=$(jq .input_tp < $tempDir/sample.json | tr -d '"')
  input_lra=$(jq .input_lra < $tempDir/sample.json | tr -d '"')
  input_thresh=$(jq .input_thresh < $tempDir/sample.json | tr -d '"')

  aOpts="loudnorm=linear=true:measured_I=$input_i:measured_tp=$input_tp:measured_LRA=$input_lra:measured_thresh=$input_thresh"

  traceIt $LINENO nrmlzIt " info " "aOpts=$aOpts"

#  ## CHANGING TO MAX VOLUME DETECT
#  avgVolume=$(ffmpeg -y -i "$inFile" -map $aStream -af volumedetect -vn -sn \
#    -f mp4 /dev/null 2>&1 | grep 'max_volume:' | awk '{ print $5 }')
#  # Incase unable to detect volume level.
#  avgVolume=${avgVolume:-27}
#
#  traceIt $LINENO nrmlzIt " info " "avgVolume=$avgVolume"
#  dbAdjust=$(echo "scale=1;-9 - $avgVolume" | bc)
#  # dbAdjust=$(echo "scale=1;-33 - $avgVolume" | bc)
#  traceIt $LINENO nrmlzIt " info " "dbAdjust=$dbAdjust"
#
#  # Determine if dB adjustment is needed (0.5 is minimum amount required for adjustment)
#  dbCheck=$(echo "$dbAdjust" | tr -d -)
#  adjustDB=$(echo "$dbCheck > 0.5" | bc)
#  traceIt $LINENO nrmlzIt " info " "adjustDB=$adjustDB"
#  #set +x
  return 0
}

getMeta ()
{
  # Metadata 
  inFile=${baseName[$l]}
  traceIt $LINENO "getMeta" " info " "inFile=${inFile}"
  fTitle=$(awk -F'[()]' '{print $1}' <<< "$inFile")
  traceIt $LINENO "getMeta" " info " "fTitle=${fTitle}"
  fDate=$(awk -F'[()]' '{ print $2 }' <<< "$inFile" | awk '{ print $1 }')
  traceIt $LINENO "getMeta" " info " "fDate=${fDate}"
  mSearch="${fTitle} ${fDate}"
  metaFile="${workDir}/${inFile}.meta"
  htmlFile="${workDir}/${inFile}.html"
  unset meta_title meta_data meta_synopsis 

  mSite="https://www.themoviedb.org"

  #echo -e "\n${C8}DEBUG: googler -w \"$mSite\" -C -n 5 --np \"$mSearch\" |\
  #  grep -A1 \"$fTitle\" | grep -m 1 'https://.*\/movie'${C0}"
  urlLink=$(googler -w "$mSite" -C -n 5 --np "${mSearch}" |\
    grep -A1 "$fTitle" | grep -m 1 'https://.*\/movie' | tr -d ' ')
  curlCmd="curl -s -k $urlLink | hxnormalize -l 9999 -x >\"$htmlFile\" 2>&1"

  if [[ -n "$urlLink" ]]; then
    eval "$curlCmd"
    meta_title=$(hxselect -ic .title h2 <"$htmlFile" | w3m -dump -T 'text/html')
    # Using w3m to sanitize output.
    meta_synopsis=$(hxselect -ic .overview <"$htmlFile" | w3m -dump -cols 9999 -T 'text/html')
    releaseDate=$(hxselect -c .releases li <"$htmlFile" |\
      sed 's/<img.*\/img>//' | w3m -dump -T 'text/html' | head -n 1)
    meta_date=$(date -d "$releaseDate" +%m/%d/%Y)
    #rm "$htmlFile"
  fi
  meta_title=${meta_title:-$fTitle}
  meta_date=${meta_date:-$fDate}
  meta_synopsis=${meta_synopsis:-'No info'}
  meta_composer="the Gh0st"
  meta_comment="$complexOpts $videoOpts $audioOpts $subOpts"

  echo ";FFMETADATA1" > "$metaFile"
  metaData[0]="title=$meta_title"
  metaData[1]="date=$meta_date"
  metaData[2]="synopsis=$meta_synopsis"
  metaData[3]="comment=$meta_comment"
  metaData[4]="composer=$meta_composer"

  echo -e "\n   ${C3}urlLink: ${C7}$urlLink${C0}"
  echo -e "     ${C3}Title: ${C4}$meta_title${C0}"
  echo -e "  ${C3}Released: ${C4}$meta_date${C0}"
  echo -e "  ${C3}Synopsis: ${C2}$meta_synopsis${C0}\n"
  
  j=0
  while (( j < ${#metaData[*]} ))
  do
    echo "${metaData[$j]}" >> "$metaFile"
    j=$((j+1))
  done

  return 0
}

setOpts ()
{
  ## Set video encode options per level

  # Check if video resize is enabled (default).
  if [[ $vResize != 'true' ]]; then
    traceIt $LINENO setOpts " info " "Skipping video resize due to override."
  else
    # Resize video if larger than 1280x720 or smaller than 720x400
    if (( hSize > 1280 )); then
      vOpts="scale=1280:-2,fps=fps=24000/1001"
      CRF=$((targetCRF-1))
    elif (( hSize < 720 )); then
      vOpts="scale=720:-2,fps=fps=24000/1001"
      CRF=$((targetCRF-1))
    fi
  fi
  CRF=${CRF:-$targetCRF}

  ## Set frame rate if not resized.
  vOpts="${vOpts:-fps=fps=24000/1001}"

  # This can be used to blur logo maps.
  # Filter logo if bitmap detected.
  if [[ -e "${inDir}/${baseName[$l]}.png" ]]; then
    # shellcheck disable=SC2089
    vOpts="${vOpts},removelogo=\"${inDir}/${baseName[$l]}.png\""
  fi
  traceIt $LINENO setOpts " info " "vOpts=$vOpts"

  if [[ -n $vOpts ]]; then
    vMap="-map [vOut]"
  else
    vMap="-map $vStream"
  fi
  traceIt $LINENO setOpts " info " "vMap=$vMap"

  ## Build video codec arguments
  # EXAMPLE: videoOpts="-c:v libx264 -crf $CRF -preset $vPreset -tune $vTune \
  #          -refs 3 -maxrate $maxBitrate -bufsize $bufSize $vExtra"
  videoOpts="-c:v libx264"
  videoOpts="$videoOpts -crf $CRF"
  videoOpts="$videoOpts -preset $vPreset"
  videoOpts="$videoOpts -tune $vTune"
#  if [[ -n $vFrameRate ]]; then
#    videoOpts="$videoOpts -r $vFrameRate"
#  fi
  if [[ -n $maxBitrate ]]; then
    videoOpts="$videoOpts -maxrate $maxBitrate"
  fi
  if [[ -n $bufSize ]]; then
    videoOpts="$videoOpts -bufsize $bufSize"
  fi
#  if [[ -n $vExtra ]]; then
#    videoOpts="$videoOpts $vExtra"
#  fi
  traceIt $LINENO setOpts " info " "videoOpts=$videoOpts"

  ## Build audo codec arguments
  audioOpts="-c:a libfdk_aac"
  if [[ -n $aBitrate ]]; then
    audioOpts="$audioOpts -b:a $aBitrate"
  fi
  if [[ $aRemix != 'true' ]]; then
    audioOpts="$audioOpts -channels $aChannels"
  fi
  if [[ -n $aOpts ]]; then
    aMap="-map [aOut]"
    audioOpts="$audioOpts -ar 48k"
  else
    audioOpts='-an'
    aMap=
  fi

  traceIt $LINENO setOpts " info " "audioOpts=$audioOpts"
  traceIt $LINENO setOpts " info " "aOpts=$aOpts"
  traceIt $LINENO setOpts " info " "aMap=$aMap"

  ## Build subtitle options
  if [[ -n $sStream ]]; then
    subOpts="-c:s mov_text -metadata:s:s:0 language=eng"
  else
    subOpts="-sn"
    sMap=
  fi
  traceIt $LINENO setOpts " info " "subOpts=$subOpts"

  ## Create complex filters
  if [[ -n $aOpts ]]; then
    complexOpts="-filter_complex [$vStream]${vOpts}[vOut];[$aStream]${aOpts}[aOut]"
  else
    complexOpts="-filter_complex [$vStream]${vOpts}[vOut]"
  fi
  traceIt $LINENO setOpts " info " "complex_opts=$complexOpts"

  ## Build final map
  streamMap=$vMap
  if [[ -n $aMap ]]; then
    streamMap="$streamMap $aMap"
  fi
  if [[ -n $sMap ]]; then
    streamMap="$streamMap $sMap"
  fi
  traceIt $LINENO setOpts " info " "streamMap=$streamMap"

  encodeOpts="$videoOpts $audioOpts $subOpts"
  traceIt $LINENO setOpts " info " "encodeOpts=$encodeOpts"

  return 0
}

encodeIt ()
{
  inFile="${fullName[$l]}"

  if [[ ! -d "${outDir[$l]}" ]]; then
    mkdir -p "${outDir[$l]}"
    chown rp01:admins "${outDir[$l]}"
    chmod 775 "${outDir[$l]}"
  fi
  if [[ $Q != 'HQ' ]]; then 
    outFile="${outDir[$l]}/${baseName[$l]}.mp4"
    echo -e "         ${C3}Output:${C6} ...${baseDir[$l]}/${baseName[$l]}.mp4${C0}\n"
  else
    outFile="${outDir[$l]}/${baseName[$l]}-∞.mp4"
    echo -e "         ${C3}Output:${C6} ...${baseDir[$l]}/${baseName[$l]}-∞.mp4${C0}\n"
  fi

  tempOut="$tempDir/converting.mp4"

  traceIt $LINENO encdeIt " CMD  " "> ffmpeg -hide_banner -y -loglevel quiet -stats -i \"$inFile\" -i \"$metaFile\" -map_metadata 1 $complexOpts $encodeOpts $streamMap \"$outFile\""

  echo -e "                                     total time=${C4}$duration${C0}"
  # shellcheck disable=SC2086,SC2090
  ffmpeg -hide_banner -y -loglevel quiet -stats -i "$inFile" -i "$metaFile" \
    -map_metadata 1 $complexOpts $encodeOpts $streamMap "$tempOut"
  STATUS=$?

  echo ""
  displayIt "ffmpeg encoded ${fileName[$l]}"

  if (( STATUS > 0 )); then
    killWait 1
    logIt "Re-encoding for $inFile failed!"
    traceIt $LINENO encdeIt "ERROR!" "STATUS=$STATUS, ffmpeg failed."
    echo -e "> ${C5}ffmpeg -y -i \"$inFile\" -i \"$metaFile\" -map_metadata 1 \
      $complexOpts $encodeOpts $streamMap \"$tempOut\"${C0}\n"
    #exit 9
  else
    mv "$tempOut" "$outFile"
    killWait 0
    origSize=$(du -b "$inFile" | cut -f1)
    newSize=$(du -b "$outFile" | cut -f1)
    diff=$(echo "scale=4; (($newSize - $origSize)/$origSize)*100" | bc | sed -r 's/0{2}$//')
    origHuman="$(du -h "$inFile" | cut -f1)"
    newHuman="$(du -h "$outFile" | cut -f1)"
    if (( $(echo "$diff < 0" | bc) )); then
      {
        echo "-------------------------"
        echo -e "Orig Size: $origHuman // New Size: $newHuman // ${C1}File decreased by: $(echo "- $diff" | bc)%${C0}"
        echo "-------------------------"
      } | tee -a "$logFile"
    else
      {
        echo "-------------------------" | tee -a "$logFile"
        echo -e "Orig Size: $origHuman // New Size: $newHuman // ${C5}File increased by: ${diff}%${C0}"
        echo "-------------------------"
      } | tee -a "$logFile"
    fi

    rm "$probeFile" "$dataFile" "$metaFile" "$htmlFile" >/dev/null 2>&1
    unset sMap aMap vMap

    {
      mkdir -p "$doneDir/${baseDir[$l]}"
      chgrp -R admins "$doneDir/${baseDir[$l]}"
      mv "${fullName[$l]}" "$doneDir/${baseDir[$l]}/"
    } >> "$traceLog" 2>&1

    logIt "outFile = $outFile"
    # Setting permission on outFile.
    chown rp01:admins "$outFile"
    chmod 0664 "$outFile"
  fi

  return $STATUS
}

usage()
{
  cat << EOM
NAME
    $0 - video converter

SYNOPSIS
    $0 [OPTION]

DESCRIPTION
    Re-encodes video files to sane/portable parameters.

    -h, --help
        This documentation.

    --hq
        Will re-encode video with high quality settings.

    --lq
        Will re-encode video with low quality settings.

    -m, --movie
        Will look for feature lenth movies in configured directory.

    -o, --other
        Will look for other type video files in configured directory.

    -s, --series
        Will look for series shows in configured directory.
        
    -v, --video
        Will look for video files in configured directory.

    -x. --restrict
        Will look for restricted videos in configured directory.

AUTHOR
    Written by Richard L. Paxton.

EXAMPLE
    The following would search for movie files and re-encode them at high quality.
    $0 -m --hq

EOM
  exit 1
}

## Checking for required packages.
command -v ffmpeg >/dev/null 2>&1 || { echo "ERROR: Unable to detect ffmpeg, bailing." >&2; exit 1; }
command -v googler >/dev/null 2>&1 || { echo "ERROR: googler is not installed, bailing." >&2; exit 1; }
command -v hxnormalize > /dev/null 2>&1 || { echo "ERROR: html-xml-utils is not installed, bailing." >&2; exit 1; }
command -v w3m > /dev/null 2>&1 || { echo "ERROR: w3m is not installed, bailing." >&2; exit 1; }


###  START OF MAIN  ###
# Check for command line arguments.
if [ "$#" -lt 1 ]; then
  usage
fi
## Get arguments.
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
#    -b | --bitrate) # Target bitrate
#      targetBitrate=${2:-48}
#      shift 2
#      ;;
    -h | --help) #Display help
      usage
      ;;
    --hq) #Set high quality override
      Q='HQ'
      shift
      ;;
    --lq)  #Set low quality override
      Q='LQ'
      shift
      ;;
    -m | --movie) #Process movies
      inDir="$searchDir/features"
      aBitrate='160k'
      aRemix=true
      bufSize='2m'
      maxBitrate='8m'
      targetCRF=22
      vPreset='medium'
      vResize=true
      vTune='film'
      shift
      ;;
    -o | --other) #Process other videos
      inDir="$searchDir/other"
      aBitrate='128k'
      aRemix=true
      bufSize='2m'
      maxBitrate='6m'
      targetCRF=22
      vPreset='medium'
      vResize=true
      vTune='film'
      shift
      ;;
    -s | --series) #tv series encodes
      inDir="$searchDir/series"
      aBitrate='128k'
      aRemix=true
      bufSize='2m'
      maxBitrate='8m'
      targetCRF=23
      vPreset='medium'
      vResize=true
      vTune='film'
      shift
      ;;
    -v | --video) #video files
      inDir="$searchDir/video"
      aBitrate='160k'
      aRemix=true
      bufSize='2m'
      maxBitrate='8m'
      targetCRF=21
      vPreset='medium'
      vResize=false
      vTune='film'
      shift
      ;;
    -x | --restricted) #restriced videos
      inDir="$searchDir/restricted"
      aBitrate='92k'
      aRemix=true
      bufSize='2m'
      maxBitrate='4m'
      targetCRF=23
      vPreset='fast'
      vResize=true
      vTune='film'
      shift
      ;;
    *)  #Unknown option
      echo -e "${C5}ERROR: 10 - Unknown option '$1'${C0}"
      usage
      ;;
  esac

  if [[ $Q == 'HQ' ]]; then
      aBitrate='192k'
      aRemix=false
      targetCRF=20
      vPreset='slower'
      vResize=false
      vTune='film'
    elif [[ $Q == 'LQ' ]]; then
      aBitrate='92k'
      aRemix=true
      bufSize='2m'
      maxBitrate='2m'
      targetCRF=23
      vPreset='medium'
      vResize=true
      vTune='film'
  fi

done

# Video Defaults unless overridden
# targetVBR=3
# vExtra='profile:v high -level 3.2'

if [[ $UID -gt 0 ]]; then
  echo -e "Must run as root user for file permissions."
  exit 2
fi

traceIt $LINENO " MAIN  " " info " "*** START OF NEW RUN ***"
echo -e "${C3}\nStarting run of ${C6}Video Converter${C0}"
umask 002

displayIt "Collecting list of files to process"
getFiles
killWait 0

l=0
while (( l < ${#fullName[*]} )); do
  traceIt $LINENO " MAIN  " " info " "START OF LOOP: $((l+1)) of $((${#fullName[*]}+1))"
  traceIt $LINENO " MAIN  " " info " "baseName=${baseName[$l]}"
  echo "" >> $logFile
  logIt "v----------------------------------------------------------v"
  logIt "Start of ${baseName[$l]}"
  logIt "------------------------------------------------------------"
  logIt "inFile=${fullName[$l]}"

  echo -e "\nFile $((l+1)) of $((${#fullName[*]}+1))"
  displayIt "Processing:" "${baseDir[$l]}/${baseName[$l]}"
  probeIt 
  killWait 0

  displayIt "Normalizing audio track"
  if normalizeIt; then
    killWait 0
  else
    killWait 2
  fi

  displayIt "Setting encode filters"
  setOpts
  killWait 0
  getMeta "${fullName[$l]}"
  echo -e "     ${C3}Stream map:${C6} $streamMap${C0}"
  echo -e "     ${C3}Video Opts:${C6} $videoOpts${C0}"
  echo -e "     ${C3}Audio Opts:${C6} $audioOpts${C0}"
  echo -e "       ${C3}Sub Opts:${C6} $subOpts${C0}"
  echo -e "${C3}Complex Filters:${C6} $complexOpts${C0}"

  encodeIt "${fullName[$l]}"

  logIt "------------------------------------------------------------"
  logIt "End of ${baseName[$l]} "
  logIt "^----------------------------------------------------------^"
  traceIt $LINENO " MAIN  " " info " "END OF LOOP: $((l+1))"
  echo "" >> "$traceLog"
  echo -e "  ${C2}Done${C0}"
  ((l++))
done

## Clean empty incoming directories.
find "$inDir/" -type d -empty -delete

echo -e "${C3}End of Video Converter run.${C0}"
exit 0
