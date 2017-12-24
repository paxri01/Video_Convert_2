#!/bin/bash
# set -x

# NOTE: Work-in-progress, still dinking with this....

# DESCRIPTION:  This script utilized ffmpeg to re-encode videos to the following:
#               Convert video to H.264, resize to minimum of 720 hSize and max of 1280 hSize,
#               with a target CRF of 20 and buffer size of 1500.  This means that the video
#               should play on all DLNA servers and TVs.
#               Convert audio to AAC, bitRate of 128Kbs.
#               If English subtitles are detected, it will also map those into output.

vResize=true     #Resize video to >= 720x400 and <= 1280x720.
aRemix=true      #Downmix multi-channel to stereo.
# H.264 CRF: Constant Rate Factor, encode video based on quality vs. size. Range: 0-51, where
# 0 = lossless and 51 = worst quality possible. Sane values 17-28. Resizing will decrease by 1.
targetCRF=23
# H.264 Preset: Used to set compression ratio, possible values: ultrafast, superfast, veryfast,
# faster, fast, medium (default), slow, slower, veryslow. Use slowest you have patience for.
vPreset='medium'
# H.264 Tune: Used to optionally tweak video encoding, possible values: film, animation, grain,
# stillimage, fastdecode, zerolatency. Unset for other types of video.
# vTune='-tune film'
# H.264 Profile: Manually set profile level
# vProfile='-profile:v high -level 4.1'
maxBitrate='8m'  #Maximum video bit rate in Kb/s. OrigBitrate <= outBitrate <= maxBitrate. 
bufSize='2m'     #Size of buffer receiver can support in Kb, used to limit stream bitrate.
# aBitrate='160k'  #Set audio bitrate
targetVBR=3      #Audio variable bit rate, range 1-5 (5=highest quality)

# Info: http://blog.mediacoderhq.com/h264-profiles-and-levels/
# vExtra='-profile:v high -level 3.2'

typeset streamMap baseName outFile encodeOpts videoOpts audioOpts vFrameRate fullName \
	fileName directory extension 
typeset -i i=0 j=0 l=0 HQ=0 Audio=0 subTitle=0

while [[ $# -gt 0 ]]; do
  key=$1
  case $key in 
    -t | --tv) #re-encode TV Shows
      inDir="/mnt/usenet/extract/TV Shows"
      outDir="/nas/multimedia"
      workDir='/mnt/usenet/Encode'
      # vTune=film
      # vPreset=medium
      # targetCRF=23
      # vExtra='-profile:v high -level 3.2'
      # fastStart=true
      shift
      ;;
    -m | --movie) #re-encode movies
      inDir='/mnt/usenet/extract/Movies'
      outDir='/nas/multimedia'
      workDir='/mnt/usenet/Encode'
      vTune=film
      vPreset=slow
      targetCRF=22
      # targetVBR=3
      vExtra='-profile:v high -level 3.2'
      shift
      ;;
    --feat) #re-encode adult movies
      inDir='/mnt/usenet/extract/Features'
      outDir='/nas/multimedia/After Dark'
      workDir='/mnt/usenet/Encode'
      # vTune=film
      # vPreset=medium
      targetVBR=2
      # targetCRF=23
      shift
      ;;
    --soft) #re-encode adult TV Shows
      inDir="/mnt/usenet/extract/Softcore"
      outDir="/nas/multimedia/After Dark"
      workDir='/mnt/usenet/Encode'
      # vTune=film
      # vPreset=medium
      targetVBR=2
      # targetCRF=23
      shift
      ;;
    --hard) #re-encode adult videos
      inDir='/mnt/usenet/extract/Hardcore'
      outDir='/nas/multimedia/After Dark'
      workDir='/mnt/usenet/Encode'
      # vTune=film
      # vPreset=medium
      targetCRF=22
      targetVBR=2
      maxBitrate='4m'
      shift
      ;;
    -s) # smut
      inDir='/mnt/usenet/extract/smut'
      outDir='/video/smut'
      workDir='/video/temp'
      # vTune=film
      # vPreset=medium
      targetCRF=22
      targetVBR=2
      shift
      ;;
    -hq | --hq) #Override for high quality output
      HQ=1
      shift
      ;;
    *) # Unknown
      echo "USAGE: $0 [ -t | -m | -s | --feat | --soft | --hard ]"
    exit 1
    ;;
  esac
done

# Directory settings
doneDir='/mnt/usenet/done'
logFile="$workDir/encode.log"
traceLog="$workDir/$(date +%Y%m%d)_trace.log"
inFiles="$workDir/inFiles"

# Video settings
range="-ss 04:00 -t 02:00"

# Misc settings
pad=$(printf '%0.1s' "."{1..100})
padlength=100
interval=.5
rPID=""
trap 'deadJim' 1 2 3 15

# HQ Overrides
if [[ $HQ -eq 1 ]]; then
  vTune=film
  vPreset=slower
  vResize=false
  aRemix=false
  targetCRF=18
  targetVBR=5
  vExtra='-profile:v high -level 4.1'
  unset maxBitrate bufSize
fi

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
  find "$inDir" \
    -iregex '.*.\(mgp\|mp4\|wmv\|avi\|mpg\|mov\|mkv\|flv\|webm\|ts\)' \
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
  rm -f "$probeFile" "$dataFile" >/dev/null 2>&1
  echo -e "input: $inFile\n" > "$probeFile"
  echo -e "input: $inFile\n" > "$dataFile"
  ffprobe -show_entries streams -sexagesimal -of flat "$inFile" > "$probeFile" 2>&1
  sed -i 's/\"//g' "$probeFile"
  chmod 0644 "$probeFile"

  # Collect number of streams and type
  stream=( $(grep 'codec_type' "$probeFile") )

  duration=$(grep 'Duration' "$probeFile" | awk -F',' '{print $1}' | awk '{print $2}')
  traceIt $LINENO probeIt " info " "duration=$duration"

  j=0; Audio=0; subTitle=0; unset sample streamMap
  while (( j < ${#stream[*]} )); do
    # set -x
    # Assuming only 1 video stream.
    if [[ $(grep -c 'video' <<< ${stream[$j]}) -eq 1 ]]; then
      # videoMap="0:${j}"
      streamMap="$streamMap -map 0:${j}"
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
    elif [[ $(grep -c 'audio' <<< ${stream[$j]}) -eq 1 && $Audio -eq 0 ]]; then
      streamMap="$streamMap -map 0:${j}"
      traceIt $LINENO probeIt " info " "audioMap=0:$j"
      sample=$(grep "stream\.${j}\.sample_rate=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "sample=$sample"
      aBitRate=$(grep -m 1 "stream\.${j}\.bit_rate=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "aBitRate=$aBitRate"
      aChannels=$(grep "stream\.${j}\.channels=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "aChannels=$aChannels"
      aLanguage=$(grep "stream\.${j}\..*language=" "$probeFile" | awk -F'=' '{print $2}')
      traceIt $LINENO probeIt " info " "aLanguage=$aLanguage"
      Audio=1
    elif [[ $(grep -c 'subtitle' <<< ${stream[$j]}) -eq 1 ]]; then
    # elif [[ $(grep -c 'subtitle' <<< ${stream[$j]}) -eq 1 && $subTitle -eq 0 ]]; then
      sCodec=$(grep "stream\.${j}\.codec_name=" "$probeFile" | awk -F'=' '{print $2}')
      sLanguage=$(grep "stream\.${j}\..*language=" "$probeFile" | awk -F'=' '{print $2}')
      # Cannot convert bitmap subtitles to text based within ffmpeg.
      if [[ $sLanguage =~ (en|eng) && $sCodec != *'pgs'* ]]; then
        streamMap="$streamMap -map 0:${j}"
        traceIt $LINENO probeIt " info " "subMap=0:$j"
        subTitle=1
        #TODO add counter for number of English subtitles detected.
      fi
    fi
    ((j++))
    # set +x
  done

  traceIt $LINENO probeIt " info " "streamMap=$streamMap"

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
streamMap=$streamMap
EOinfo

  return 0
}

normalizeIt ()
{
  # set -x
  inFile="${fullName[$l]}"
  if (( Audio == 0 )); then
    logIt "No audio to normalize, skipping."
    return 1
  fi

  cat << EOcmd >> "$traceLog"
> ffmpeg -y $range -i "$inFile" $streamMap -af volumedetect -vn -sn -f mp4 /dev/null 2>&1 |\\
grep 'mean_volume' | awk -F':' '{print \$2}' | awk '{print \$1}'
EOcmd

  # shellcheck disable=SC2086
  avgVolume=$(ffmpeg -y $range -i "$inFile" $streamMap -af volumedetect -vn -sn -f mp4 /dev/null 2>&1 |\
    grep 'mean_volume' | awk -F':' '{print $2}' | awk '{print $1}')
  # Incase unable to detect volume level.
  avgVolume=${avgVolume:-27}

  traceIt $LINENO nrmlzIt " info " "avgVolume=$avgVolume"
  dbAdjust=$(echo "scale=1;-27 - $avgVolume" | bc)
  # dbAdjust=$(echo "scale=1;-33 - $avgVolume" | bc)
  traceIt $LINENO nrmlzIt " info " "dbAdjust=$dbAdjust"

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

  # Check if video resize is enabled (default).
  if [[ $vResize != 'true' ]]; then
    traceIt $LINENO flterIt " info " "Skipping video resize due to override."
    return 0
  fi

  inFile=$1
  traceIt $LINENO flterIt " info " "inFile=\"$inFile\""
 
  # This can be used to blur logo maps.
  # Filter logo if bitmap detected.
  #if [[ -e "$inDir/${baseName[$l]}.png" ]]; then
  #  filterOpts="-vf removelogo=${baseName[$l]}.png"
  #fi

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
  metaData[1]="comment=Encoded on $(date -R)"
  metaData[2]="synopsis=$videoOpts $audioOpts $subOpts"
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
  unset audioOpts videoOpts encodeOpts

  # Set video options
  videoOpts="-c:v libx264"
  if [[ ! -z $vPreset ]]; then
    videoOpts="$videoOpts -preset $vPreset"
  fi
  if [[ ! -z $vTune ]]; then
    videoOpts="$videoOpts -tune $vTune"
  fi
  if [[ ! -z $vFrameRate ]]; then
    videoOpts="$videoOpts -r $vFrameRate"
  fi
  if [[ ! -z $CRF ]]; then
    videoOpts="$videoOpts -crf $CRF"
  fi
  if [[ ! -z $maxBitrate ]]; then
    videoOpts="$videoOpts -maxrate $maxBitrate"
  fi
  if [[ ! -z $bufSize ]]; then
    videoOpts="$videoOpts -bufsize $bufSize"
  fi
  if [[ ! -z $vExtra ]]; then
    videoOpts="$videoOpts $vExtra"
  fi
  if [[ $fastStart == 'true' ]]; then
    videoOpts="$videoOpts -movflags faststart"
  fi

  # videoOpts="-c:v libx264 -preset $vPreset -tune $vTune -r $vFrameRate -refs 3 -crf $CRF -maxrate ${outBitRate}k -bufsize ${bufSize}k"
  traceIt $LINENO setOpts " info " "videoOpts=$videoOpts"

  # Set audo options
  audioOpts="-c:a libfdk_aac"
  if [[ ! -z $targetVBR ]]; then
    # audioOpts="$audioOpts -b:a $aBitrate"
    audioOpts="$audioOpts -vbr $targetVBR"
  fi
  if [[ $aRemix != 'true' ]]; then
    audioOpts="$audioOpts -channels $aChannels"
  fi
  if [[ ! -z $dbAdjust ]]; then
    audioOpts="$audioOpts -af volume=${dbAdjust}dB"
  fi
  if (( Audio == 0 )); then
    audioOpts="-an"
  fi

  traceIt $LINENO setOpts " info " "audioOpts=$audioOpts"

  # Set subtitle options
  if (( subTitle == 1 )); then
    # streamMap="-analyzeduration 100M -probesize 100M $streamMap"
    subOpts="-c:s mov_text -metadata:s:s:0 language=eng"
  else
    subOpts="-sn"
  fi

  traceIt $LINENO setOpts " info " "subOpts=$subOpts"

  encodeOpts="$streamMap $videoOpts $filterOpts $audioOpts $subOpts"
  traceIt $LINENO setOpts " info " "encodeOpts=$encodeOpts"

}

encodeIt ()
{
  inFile=$1
  mkdir -p "$outDir/${directory[$l]}"
  # Setting permission on share directory.
  chmod -R 0775 "$outDir/${directory[$l]}"
  chown -R 10001107:serviio "$outDir/${directory[$l]}"
  if [[ $aRemix == 'true' ]]; then 
    outFile="${outDir}${directory[$l]}/${baseName[$l]}-ø.mp4"
    echo -e "         ${C3}Output:${C6} ...${directory[$l]}/${baseName[$l]}-ø.mp4${C0}\n"
  else
    outFile="${outDir}${directory[$l]}/${baseName[$l]}-∞.mp4"
    echo -e "         ${C3}Output:${C6} ...${directory[$l]}/${baseName[$l]}-∞.mp4${C0}\n"
  fi

  traceIt $LINENO encdeIt " info " "ffmpeg -y -i \"$inFile\" -i \"$metaFile\" -map_metadata 1 $encodeOpts \"$outFile\""

  echo -e "                                     total time=${C4}$duration${C0}"
  # shellcheck disable=SC2086
  ffmpeg -hide_banner -y -loglevel quiet -stats \
    -i "$inFile" \
    -i "$metaFile" \
    -map_metadata 1 \
    $encodeOpts \
    "$outFile"
  STATUS=$?

  origSize=$(du -b "$inFile" | cut -f1)
  newSize=$(du -b "$outFile" | cut -f1)
  diff=$(echo "scale=4; (($newSize - $origSize)/$origSize)*100" | bc | sed -r 's/0{2}$//')
  if (( $(echo "$diff < 0" | bc) )); then
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

  displayIt "Processing:" "${directory[$l]}/${baseName[$l]}"
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
  echo -e "     ${C3}Stream map:${C6}$streamMap${C0}"
  echo -e "     ${C3}Video Opts:${C6} $videoOpts${C0}"
  echo -e "    ${C3}Filter Opts:${C6} $filterOpts${C0}"
  echo -e "     ${C3}Audio Opts:${C6} $audioOpts${C0}"
  echo -e "       ${C3}Sub Opts:${C6} $subOpts${C0}"

  encodeIt "${fullName[$l]}"

  logIt "------------------------------------------------------------"
  logIt "End of ${baseName[$l]}"
  logIt "^----------------------------------------------------------^"
  traceIt $LINENO " MAIN  " " info " "END OF LOOP: $l"
  echo -e "  ${C2}Done${C0}"
  ((l++))
done

echo -e "${C3}End of Video Converter run.${C0}"
exit 0
