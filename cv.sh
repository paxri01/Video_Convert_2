#!/bin/bash
# set -x

typeset streamMap encodeOpts videoOpts codecOpts audioOpts vFrameRate
typeset -i j=0 noAudio=0

# File settings
inFile="$1"
logFile=".${inFile%.*}.log"
traceLog="$logFile"

umask 0022

# Video settings
# HQ=0
vPreset=medium
vTune=film
targetCRF=20
maxBitrate=30000
bufSize=1500
range="04:00 -t 04:00"

# Add some colors
# C1='\033[38;5;040m'  # Green
# C2='\033[38;5;243m'  # Grey
C3='\033[38;5;254m'  # White
# C4='\033[38;5;184m'  # Yellow
# C5='\033[38;5;160m'  # Red
C6='\033[38;5;165m'  # Purple
# C7='\033[38;5;063m'  # Blue
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

probeIt ()
{
  # Gather video information
  traceIt $LINENO probeIt " info " "inFile=\"$inFile\""

  # probeFile="$inDir/${baseName[$l]}.probe"
  probeFile=".${inFile}.probe"
  dataFile=".${inFile}.data"
  echo -e "input: $inFile\n" | tee "$probeFile" "$dataFile" > /dev/null

  cat << EOcmd >> "$logFile"
> ffprobe -hide_banner -show_entries streams -sexagesimal -of flat "$inFile" | tr -d '"'
EOcmd

  ffprobe -hide_banner \
    -show_entries streams \
    -sexagesimal \
    -of flat "$inFile" 2>/dev/null | tr -d '"' >> "$probeFile"

  # Collect number of streams and type
  #stream=( $(grep 'codec_type' "$probeFile") )
  mapfile -t stream < <(grep 'codec_type' "$probeFile")

  # Process all streams in video file
  j=0 
  while (( j < ${#stream[*]} )); do
    # TODO Change to case select
    #if [[ $(grep -c 'video' <<< "${stream[$j]}") -eq 1 ]]; then
    if grep -q 'video' <<< "${stream[$j]}"; then
      videoMap="0:${j}"
      traceIt $LINENO probeIt " info " "videoMap=$videoMap"
      hSize=$(grep "\.${j}\.width" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "hSize=$hSize"
      vSize=$(grep "\.${j}\.height" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vSize=$vSize"
      videoSize="${hSize}x${vSize}"
      traceIt $LINENO probeIt " info " "videoSize=$videoSize"
      vBitRate=$(grep "\.${j}\.bit_rate=" "$probeFile" | awk -F'=' '{print $2}')
      if [[ $vBitRate == "N/A" ]]; then
        vBitRate=$(grep 'bitrate' "$probeFile" | awk -F: '{print $6}' | cut -c 2- | awk '{print $1}')
      else
        vBitRate=$(( vBitRate/1024 ))
      fi
      traceIt $LINENO probeIt " info " "vBitRate=$vBitRate"
      vFrameRate=$(grep "\.${j}\.r_frame_rate=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vFrameRate=$vFrameRate"
      duration=$(grep "\.${j}\.duration=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "duration=$duration"
      vLanguage=$(grep "\.${j}\.language=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vLanguage=$vLanguage"
    # Assumed first audio stream is good
    elif [[ $(grep -c 'audio' <<< "${stream[$j]}") -eq 1 ]]; then
      audioMap="0:${j}"
      traceIt $LINENO probeIt " info " "audioMap=$audioMap"
      sample=$(grep "\.${j}\.sample_rate=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "sample=$sample"
      aBitRate=$(grep "\.${j}\.bit_rate=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "aBitRate=$aBitRate"
      aLanguage=$(grep "\.${j}\.language=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "aLanguage=$aLanguage"
    fi
    ((j++))
  done

  if [[ -z $audioMap ]]; then
    # No audio found
    streamMap="-map $videoMap"
    noAudio=1
  else
    streamMap="-map $videoMap -map $audioMap"
    noAudio=0
  fi
  traceIt $LINENO probeIt " info " "streamMap=$streamMap"

  cat << EOinfo >> "$dataFile" 
--- Stream Info ---
videoSize=$videoSize
hSize=$hSize
vSize=$vSize
vBitRate=$vBitRate
sample=$sample
aBitRate=$aBitRate
duration=$duration
streamMap=$streamMap
EOinfo
  return 0
}

normalizeIt ()
{
  # set -x
  if (( noAudio == 1 )); then
    logIt "No audio to normalize, skipping."
    return 1
  fi

  echo -e "${C3}Checking audio levels${C0}"
  cat << EOcmd >> "$logFile"
> ffmpeg -hide_banner -y -ss $range -i '$inFile' $streamMap -af volumedetect -vn -sn -f mp4 /dev/null 2>&1 | \
grep 'mean_volume' | awk -F':' '{print \$2}' | awk '{print \$1}'
EOcmd

  # shellcheck disable=SC2086
  avgVolume=$(ffmpeg -hide_banner -y -ss $range -i "$inFile" $streamMap \
    -af volumedetect -vn -sn -f mp4 /dev/null 2>&1 | \
    grep 'mean_volume' | awk -F':' '{print $2}' | awk '{print $1}')

  traceIt $LINENO nrmlzIt " info " "avgVolume=$avgVolume"
  dbAdjust=$(echo "scale=1;-27 - $avgVolume" | bc)
  traceIt $LINENO nrmlzIt " info " "dbAdjust=$dbAdjust"
  # dbAdjust=$(echo "scale=1;-33 - $avgVolume" | bc)

  # Determine if dB adjustment is needed (0.5 is minimum amount required for adjustment)
  dbCheck=$(echo "$dbAdjust" | tr -d -)
  adjustDB=$(echo "$dbCheck > 0.5" | bc)
  traceIt $LINENO nrmlzIt " info " "adjustDB=$adjustDB"

  # set +x
  return 0
}

filterIt ()
{
  unset filterOpts
  
  # # Filter logo if bitmap detected.
  # if [[ -e "$inDir/${baseName[$l]}.png" ]]
  # then
  #   filterOpts="-vf removelogo=${baseName[$l]}.png"
  # fi

  # Resize video if larger than 1280x720 or smaller than 720x400
  if (( hSize > 1280 )); then
    filterOpts="-vf scale=1280:trunc(ow/a/2)*2"
    CRF=$((targetCRF-1))
  elif (( hSize < 720 )); then
    filterOpts="-vf scale=720:trunc(ow/a/2)*2"
    CRF=$((targetCRF-1))
  else
    # Reset to original value
    CRF=$targetCRF
  fi
  traceIt $LINENO flterIt " info " "filterOpts=$filterOpts"

  return 0
}

getMeta ()
{
  # Metadata 
  # Oh, you have no idea how painful this was to debug and make work...
  metaFile=".${inFile}.meta"
  traceIt $LINENO getMeta " info " "metaFile=$metaFile"
  echo ";FFMETADATA1" > "$metaFile"
  metaData[0]="date=$(date '+%Y-%m-%d')"
  metaData[1]="comment=(see synopsis for encode opts)"
  metaData[2]="synopsis=$videoOpts $codecOpts $audioOpts"
  metaData[3]="title=$inFile"
  metaData[4]="composer=theGh0st"

  j=0
  while (( j < ${#metaData[*]} ))
  do
    logIt "getMetadata.metaData[$j]=${metaData[$j]}"
    echo "${metaData[$j]}" >> "$metaFile"
    j=$((j+1))
  done

  return 0
}

setOpts ()
{
  unset audioOpts codecOpts videoOpts encodeOpts
  traceIt $LINENO setOpts " info " "vBitRate=$vBitRate"
  traceIt $LINENO setOpts " info " "maxBitrate=$maxBitrate"
  if (( vBitRate > maxBitrate )); then
    outBitRate=$maxBitrate
  else
    outBitRate=$vBitRate
  fi
  traceIt $LINENO setOpts " info " "outBitRate=$outBitRate"
  # videoOpts="-c:v libx264 -preset $vPreset -tune $vTune -r 24000/1001 -refs 3 -crf $CRF -maxrate ${outBitRate} -bufsize ${bufSize}k"
  videoOpts="-c:v libx264 -preset $vPreset -tune $vTune -r $vFrameRate -refs 3 -crf $CRF -maxrate ${outBitRate}k -bufsize ${bufSize}k"
  traceIt $LINENO setOpts " info " "videoOpts=$videoOpts"

  codecOpts="-x264opts ref=3:deblock=0,-1"
  traceIt $LINENO setOpts " info " "codecOpts=$codecOpts"

  if (( noAudio == 0 && adjustDB == 1 )); then
    audioOpts="-c:a libfdk_aac -b:a 128k -af volume=${dbAdjust}dB"
  elif (( noAudio == 0 && adjustDB == 0 )); then
    audioOpts="-c:a libfdk_aac -b:a 128k"
  else
    audioOpts="-an"
  fi
  traceIt $LINENO setOpts " info " "audioOpts=$audioOpts"

  encodeOpts="$streamMap $videoOpts $codecOpts $audioOpts $filterOpts -sn"
  traceIt $LINENO setOpts " info " "encodeOpts=$encodeOpts"
  # logIt "encodeOpts=$encodeOpts"

  return 0
}

encodeIt ()
{
  outFile="${inFile%.*}-opt.mp4"
  # Check for skip sample option or video mode
  logIt "orig size = $(du -h "$inFile" | cut -f1)"

  echo -e "${C3}Re-encoding ${C6}$inFile${C0}"
  cat << EOcmd >> "$logFile"
> ffmpeg -y -loglevel fatal -i "$inFile" -i "$metaFile" -map_metadata 1 $encodeOpts "$outFile"
EOcmd

  # ffmpeg -hide_banner -y -loglevel fatal -i "$inFile" -i "$metaFile" \
  # shellcheck disable=SC2086
  ffmpeg -y -loglevel fatal -i "$inFile" -i "$metaFile" -map_metadata 1 $encodeOpts "$outFile"
  STATUS=$?

  if (( STATUS > 0 )); then
    logIt "ERROR: $STATUS  Re-encoding for $inFile failed!"
  else
    logIt " new size = $(du -h "$outFile" | cut -f1)"
    rm "$probeFile" "$dataFile" "$metaFile"
  fi

  return $STATUS
}


###  START OF MAIN  ###
echo -e "${C3}Converting ${C6}$inFile${C0}" | tee "$logFile"
traceIt $LINENO " MAIN  " " info " "Converting $inFile"
probeIt "$inFile"
normalizeIt "$inFile"
filterIt "$inFile"
setOpts
getMeta "$inFile"
encodeIt "$inFile"

