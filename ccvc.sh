#!/bin/bash
# set -x

# NOTE: Work-in-progress, still dinking with this....


typeset streamMap baseName outFile encodeOpts videoOpts codecOpts audioOpts vFrameRate fullName \
	fileName directory extension 
typeset -i i=0 j=0 l=0 noAudio=0

key=$1

case $key in 
  -t | --tv) #re-encode TV Shows
    inDir="/mnt/usenet/extract/TV Shows"
    outDir="/nas/multimedia"
    workDir='/mnt/usenet/Encode'
    vPreset=medium
    vTune=film
    targetCRF=20
    maxBitrate=30000
    bufSize=1500
    shift
    ;;
  -m | --movie) #re-encode movies
    inDir='/mnt/usenet/extract/movies'
    outDir='/nas/multimedia'
    workDir='/mnt/usenet/Encode'
    vPreset=medium
    vTune=film
    targetCRF=20
    maxBitrate=30000
    bufSize=1500
    shift
    ;;
  --feat) #re-encode movies
    inDir='/mnt/usenet/extract/Features'
    outDir='/nas/multimedia/After Dark'
    workDir='/mnt/usenet/Encode'
    vPreset=medium
    vTune=film
    targetCRF=20
    maxBitrate=30000
    bufSize=1500
    shift
    ;;
  --soft) #re-encode TV Shows
    inDir="/mnt/usenet/extract/Softcore"
    outDir="/nas/multimedia/After Dark"
    workDir='/mnt/usenet/Encode'
    vPreset=medium
    vTune=film
    targetCRF=20
    maxBitrate=30000
    bufSize=1500
    shift
    ;;
  --hard) #re-encode movies
    inDir='/mnt/usenet/extract/Hardcore'
    outDir='/nas/multimedia/After Dark'
    workDir='/mnt/usenet/Encode'
    vPreset=medium
    vTune=film
    targetCRF=20
    maxBitrate=30000
    bufSize=1500
    shift
    ;;
  -s) # smut
    inDir='/mnt/usenet/extract/smut'
    outDir='/video/smut'
    workDir='/video/temp'
    vPreset=medium
    vTune=film
    targetCRF=20
    maxBitrate=30000
    bufSize=1500
    shift
    ;;
  *) # Unknown
    echo "USAGE: $0 [ -t | -m | -s | --feat | --soft | --hard ]"
    exit 1
    ;;
esac

# Directory settings
doneDir='/mnt/usenet/done'
logFile="/$workDir/encode.log"
traceLog="$workDir/$(date +%Y%m%d)_trace.log"
inFiles="$workDir/inFiles"

# Video settings
# HQ=0
range="-ss 04:00 -t 02:00"

# Misc settings
pad=$(printf '%0.1s' "."{1..100})
padlength=100
interval=.5
rPID=""

# Add some colors
C1='\033[38;5;040m'  # Green
C2='\033[38;5;243m'  # Grey
C3='\033[38;5;254m'  # White
C4='\033[38;5;184m'  # Yellow
C5='\033[38;5;160m'  # Red
C6='\033[38;5;165m'  # Purple
C7='\033[38;5;063m'  # Blue
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


getFiles ()
{
  find "$inDir" \
    -iregex '.*.\(mgp\|mp4\|wmv\|avi\|mpg\|mov\|mkv\|flv\|webm\)' \
    -fprintf "$inFiles" '%h/%f\n'

  i=0
  while read LINE; do
    fileNo=$((i+1))
    fullName[$i]="$LINE"
    fileName[$i]=$(basename "${fullName[$i]}")
    directory[$i]=$(dirname "${fullName[$i]}" | sed -e "s/\/mnt\/usenet\/extract//")
    tempFile="${fileName[$i]}"
    extension[$i]="${tempFile##*.}"
    baseName[$i]="${tempFile%.*}"
    traceIt $LINENO getFles " info " "== Processing file number: [$(printf '%.3d' $fileNo)] =="
    traceIt $LINENO getFles " info " "fullName=${fullName[$i]}"
    traceIt $LINENO getFles " info " "directory=${directory[$i]}"
    traceIt $LINENO getFles " info " "fileName=${fileName[$i]}"
    traceIt $LINENO getFles " info " "baseName=${baseName[$i]}"
    traceIt $LINENO getFles " info " "extension=${extension[$i]}"
    ((i++))
  done < $inFiles
  rm $inFiles
  return 0
}

probeIt ()
{
  # Gather video information
  inFile=$1
  traceIt $LINENO probeIt " info " "inFile=\"$inFile\""

  probeFile="$workDir/${baseName[$l]}.probe"
  dataFile="$workDir/${baseName[$l]}.data"
  echo -e "input: $inFile\n" > "$probeFile"
  echo -e "input: $inFile\n" > "$dataFile"
  ffprobe -hide_banner \
    -show_entries streams \
    -sexagesimal \
    -of flat "$inFile" > "$probeFile" 2>&1
  sed -i 's/\"//g' "$probeFile"

  # Collect number of streams and type
  stream=( $(grep 'codec_type' "$probeFile") )
  
  duration=$(ffprobe "$inFile" 2>&1 | grep 'Duration' | awk -F',' '{print $1}' | awk '{print $2}')

  j=0; unset sample audioMap 
  while (( j < ${#stream[*]} )); do
    # TODO Change to case select
    # set -x
    if [[ $(grep -c 'video' <<< ${stream[$j]}) -eq 1 ]]; then
      videoMap="0:${j}"
      hSize=$(grep "\.${j}\.width" "$probeFile" | awk -F'=' '{print $2}')
      vSize=$(grep "\.${j}\.height" "$probeFile" | awk -F'=' '{print $2}')
      videoSize="${hSize}x${vSize}"
      traceIt $LINENO probeIt " info " "videoMap=$videoMap"
      traceIt $LINENO probeIt " info " "hSize=$hSize"
      traceIt $LINENO probeIt " info " "vSize=$vSize"
      traceIt $LINENO probeIt " info " "videoSize=$videoSize"
      vBitRate=$(grep "\.${j}\.bit_rate=" "$probeFile" | awk -F'=' '{print $2}')
      if [[ $vBitRate == "N/A" ]]; then
        vBitRate=$(grep 'bitrate' "$probeFile" | awk -F: '{print $6}' | cut -c 2- | awk '{print $1}')
      else
        vBitRate=$(( vBitRate/1024 ))
      fi
      vFrameRate=$(grep "\.${j}\.r_frame_rate=" "$probeFile" | awk -F'=' '{print $2}')
      # duration=$(grep "\.${j}\.duration=" "$probeFile" | awk -F'=' '{print $2}')
      vLanguage=$(grep "\.${j}\.language=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "vBitRate=$vBitRate"
      traceIt $LINENO probeIt " info " "vFrameRate=$vFrameRate"
      traceIt $LINENO probeIt " info " "duration=$duration"
      traceIt $LINENO probeIt " info " "vLanguage=$vLanguage"
    # Assumed first audio stream is good
    elif [[ $(grep -c 'audio' <<< ${stream[$j]}) -eq 1 && -z $sample ]]; then
      audioMap="0:${j}"
      sample=$(grep "\.${j}\.sample_rate=" "$probeFile" | awk -F'=' '{print $2}')
      aBitRate=$(grep "\.${j}\.bit_rate=" "$probeFile" | awk -F'=' '{print $2}')
      aLanguage=$(grep "\.${j}\.language=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "audioMap=$audioMap"
      traceIt $LINENO probeIt " info " "sample=$sample"
      traceIt $LINENO probeIt " info " "aBitRate=$aBitRate"
      traceIt $LINENO probeIt " info " "aLanguage=$aLanguage"
      set +x
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

  cat <<EOinfo >> "$dataFile"
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
  inFile=$1
  if (( noAudio == 1 )); then
    logIt "No audio to normalize, skipping."
    return 1
  fi

  cat << EOcmd >> "$traceLog"
> ffmpeg -y -i "$inFile" $streamMap \\
  -af volumedetect -vn -sn -f mp4 /dev/null |\\
  grep 'mean_volume' | awk -F':' '{print \$2}' | awk '{print \$1}'
EOcmd

  # shellcheck disable=SC2086
  avgVolume=$(ffmpeg -y $range -i "$inFile" $streamMap -af volumedetect -vn -sn -f mp4 \
    /dev/null 2>&1 | grep 'mean_volume' | awk -F':' '{print $2}' | awk '{print $1}')

  traceIt $LINENO nrmlzIt " info " "avgVolume=$avgVolume"
  dbAdjust=$(echo "scale=1;-27 - $avgVolume" | bc)
  # dbAdjust=$(echo "scale=1;-33 - $avgVolume" | bc)
  traceIt $LINENO nrmlzIt " info " "dbAdjust=$dbAdjust"

  # Determine if dB adjustment is needed (0.5 is minimum amount required for adjustment)
  dbCheck=$(echo "$dbAdjust" | tr -d -)
  adjustDB=$(echo "$dbCheck > 0.5" | bc)
  traceIt $LINENO nrmlzIt " info " "adjustDB=$adjustDB"
  return 0
}

filterIt ()
{
  unset filterOpts
  inFile=$1
  traceIt $LINENO flterIt " info " "inFile=\"$inFile\""
  
  # # Filter logo if bitmap detected.
  # if [[ -e "$inDir/${baseName[$l]}.png" ]]
  # then
  #   filterOpts="-vf removelogo=${baseName[$l]}.png"
  # fi

  # Resize video if larger than 1280x720 or smaller than 720x400
  if (( hSize > 1280 )); then
    filterOpts="-vf scale=1280:trunc\(ow/a/2\)*2"
    CRF=$((targetCRF-1))
  elif (( hSize < 720 )); then
    filterOpts="-vf scale=720:trunc\(ow/a/2\)*2"
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
  metaFile="${workDir}/${baseName[$l]}.meta"
  traceIt $LINENO getMeta " info " "metaFile=$metaFile"
  echo ";FFMETADATA1" > "$metaFile"
  metaData[0]="date=$(date '+%Y-%m-%d')"
  metaData[1]="comment=(see synopsis for encode opts)"
  metaData[2]="synopsis=$videoOpts $codecOpts $audioOpts"
  metaData[3]="title=${baseName[$l]}"
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
  videoOpts="-c:v libx264 -preset $vPreset -tune $vTune -r $vFrameRate -refs 3 \
    -crf $CRF -maxrate ${outBitRate}k -bufsize ${bufSize}k"
  # videoOpts="-c:v libx265 -preset $vPreset -r $vFrameRate -refs 3 -crf $CRF \
  #  -maxrate ${outBitRate}k -bufsize ${bufSize}k"
  traceIt $LINENO setOpts " info " "videoOpts=$videoOpts"

  # codecOpts="-x264opts ref=3:deblock=0,-1"
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
}

encodeIt ()
{
  inFile=$1
  mkdir -p "$outDir/${directory[$l]}"
  chmod -R 0775 "$outDir"
  chown -R 10001107:serviio "$outDir"
  outFile="${outDir}${directory[$l]}/${baseName[$l]}-ø.mp4"
  # Check for skip sample option or video mode
  traceIt $LINENO encdeIt " info " "ffmpeg -hide_banner -loglevel fatal -y -i \"$inFile\" -i \"$metaFile\" -map_metadata 1 $encodeOpts \"$outFile\""

  echo -e "                                     total time=${C4}$duration${C0}"
  # ffmpeg -hide_banner -y -loglevel fatal \
  # shellcheck disable=SC2086
  ffmpeg -hide_banner -y -loglevel quiet -stats \
    -i "$inFile" \
    -i "$metaFile" \
    -map_metadata 1 \
    $encodeOpts \
    "$outFile"
  STATUS=$?

  origSize=$(du "$inFile" | cut -f1)
  newSize=$(du "$outFile" | cut -f1)
  diff=$(echo "scale=4; (($newSize - $origSize)/$origSize)*100" | bc | sed -r 's/0{2}$//')
  if [[ $(echo "$diff < 0" | bc) ]]; then
    echo "-------------------------" | tee -a "$logFile"
    echo -e "File ${C1}decreased${C0} by: ${C1}$(echo "- $diff" | bc)%${C0}" | tee -a "$logFile"
    echo "-------------------------" | tee -a "$logFile"
  else
    echo "-------------------------" | tee -a "$logFile"
    echo -e "File ${C5}increased${C0} by: ${C5}${diff}%${C0}" | tee -a "$logFile"
    echo "-------------------------" | tee -a "$logFile"
  fi

  if (( STATUS > 0 )); then
    logIt "Re-encoding for $inFile failed!"
    traceIt $LINENO encdeIt "ERROR!" "STATUS=$STATUS, ffmpeg failed."
  else
    logIt "orig size = $(du -h "$inFile" | cut -f1)"
    logIt " new size = $(du -h "$outFile" | cut -f1)"
    rm "$probeFile"
    rm "$dataFile"
    rm "$metaFile"
    mv "$inFile" "$doneDir" >/dev/null 2>&1
    logIt "outFile = $outFile"
    chmod 0664 "$outFile"
    chown 10001107:serviio "$outFile"
  fi

  return $STATUS
}


###  START OF MAIN  ###
traceIt $LINENO " MAIN  " " info " "*** START OF NEW RUN ***"
echo -e "${C3}\nStarting run of ${C6}Video Converter${C0}"

displayIt "Collecting list of files to process"
getFiles
killWait 0

l=0
while (( l < ${#fullName[*]} )); do
  traceIt $LINENO " MAIN  " " info " "START OF LOOP: $l"
  # baseName[$l]="$(basename "${fullName[$l]}" | sed 's/\.[^.]*$//')"
  traceIt $LINENO " MAIN  " " info " "baseName=${baseName[$l]}"
  echo "" >> $logFile
  logIt "v----------------------------------------------------------v"
  logIt "Start of ${baseName[$l]}"
  logIt "------------------------------------------------------------"
  logIt "inFile=${fullName[$l]}"

  displayIt "Processing:" "${baseName[$l]}"
  probeIt "${fullName[$l]}"
  killWait 0

  displayIt "Normalizing audio track"
  normalizeIt "${fullName[$l]}"
  if [[ $? -gt 0 ]]; then
    killWait 2
  else
    killWait 0
  fi

  displayIt "Setting encode filters"
  filterIt "${fullName[$l]}"
  setOpts
  getMeta "${fullName[$l]}"
  killWait 0

  # displayIt "Encoding video file"
  encodeIt "${fullName[$l]}"
#  if [[ $? -gt 0 ]]; then
#    killWait 1
#  else
#    killWait 0
#  fi

  logIt "------------------------------------------------------------"
  logIt "End of ${baseName[$l]}"
  logIt "^----------------------------------------------------------^"
  traceIt $LINENO " MAIN  " " info " "END OF LOOP: $l"
  echo -e "  ${C2}Done${C0}"
  ((l++))
done

echo -e "${C3}End of Video Converter run.${C0}"

