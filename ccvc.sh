#!/bin/bash
# set -x

# NOTE: Work-in-progress, still dinking with this....

# DESCRIPTION:  This script utilized ffmpeg to re-encode videos to the following:
#               Convert video to H.264, resize to minimum of 720 hSize and max of 1280 hSize,
#               with a target CRF of 20 and buffer size of 1500.  This means that the video
#               should play on all DLNA servers and TVs.
#               Convert audio to AAC, bitRate of 128Kbs.
#               If English subtitles are detected, it will also map those into output.

typeset baseName outFile encodeOpts videoOpts audioOpts fullName fileName extension mainAudio
typeset -i i=0 j=0 l=0 noAudio=0

# Program settings
baseDir='/data2/usenet'
logDir='/var/log/convert'
searchDir="$baseDir/renamed"
workDir="$baseDir/tmp"
logFile="$logDir/ccvc.log"
traceLog="$logDir/ccvc_trace_$(date +%F).log"
doneDir="$baseDir/done"
videoDir="/video"
inFiles="$workDir/inFiles.lst"
tempDir="/video/temp"
user="serviio"
group="video"

# Audio sample range
range="-ss 01:00 -t 06:00"
#range="-t 10:00"

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
C8='\033[38;5;234m'  # Dark
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
  find "$inDir" -type f -iregex '.*.\(mgp\|mp4\|m4v\|wmv\|avi\|mpg\|mov\|mkv\|flv\|webm\|ts\|f4v\)' \
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
  inFile="$1"

  echo -e "${C8}\ncc_probe \"$inFile\"${C0}"
  cc_probe "$inFile"
  # shellcheck disable=SC1091
  source .probe.rc
  #shellcheck disable=SC2154
  cat << EOF >> "$traceLog"
## Probe results
  > fName=$fName
  > fSize=$fSize
  > duration=$duration
  > vStream=$mainVideo
  > vWidth=$vWidth
  > vHeight=$vHeight
  > vBitrate=$vBitrate
  > vFPS=$vFPS
  > vLanguage=$vLanguage
  > vMap=$vMap
  > aStream=$mainAudio
  > aBitrate=$aBitrate
  > aSample=$aSamplerate
  > aChannels=$aChannels
  > aLanguage=$aLanguage
  > aMap=$aMap
  > sMap=$sMap
EOF

  rm .probe.rc
  return 0
}

normalizeIt ()
{
  inFile=$1

  if [[ -z $mainAudio ]]; then
    noAudio='1'
    logIt "No audio to normalize, skipping."
    return 1
  fi

  # Reset noAudio flag
  noAudio=0

  traceIt $LINENO nrmlzIt " info " "Sample command:"
  cat << EOcmd >> "$traceLog"
> ffmpeg -hide_banner -y $range -i "$inFile" -vn -sn -filter:a loudnorm=print_format=json \
-f mp4 /dev/null 2>&1 | sed -n '/{/,/}/p' > "$tempDir/sample.json"
EOcmd

  # shellcheck disable=SC2086
  ffmpeg -hide_banner -y $range -i "$inFile" -vn -sn -filter:a loudnorm=print_format=json \
    -f mp4 /dev/null 2>&1 | sed -n '/{/,/}/p' > "$tempDir/sample.json"

  input_i=$(jq -r '.input_i' < $tempDir/sample.json)
  input_tp=$(jq -r '.input_tp' < $tempDir/sample.json)
  input_lra=$(jq -r '.input_lra' < $tempDir/sample.json)
  input_thresh=$(jq -r '.input_thresh' < $tempDir/sample.json)
  target_offset=$(jq -r '.target_offset' < $tempDir/sample.json)

  #aOpts="loudnorm=linear=true:measured_I=$input_i:measured_tp=$input_tp:measured_LRA=$input_lra:measured_thresh=$input_thresh"
  aOpts="loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=$input_i:measured_tp=$input_tp:measured_LRA=$input_lra:measured_thresh=$input_thresh:offset=$target_offset:linear=true"

  sudo rm "$tempDir/sample.json"

  traceIt $LINENO nrmlzIt " info " "aOpts=$aOpts"

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
  #mSearch="${fTitle} ${fDate}"
  metaFile="${workDir}/${inFile}.meta"
  htmlFile="${workDir}/${inFile}.html"
  unset meta_title meta_data meta_synopsis 

#  mSite="https://www.themoviedb.org"
#
#  #echo -e "\n${C8}DEBUG: googler -w \"$mSite\" -C -n 5 --np \"$mSearch\" |\
#  #  grep -A1 \"$fTitle\" | grep -m 1 'https://.*\/movie'${C0}"
#  urlLink=$(googler -w "$mSite" -C -n 5 --np "${mSearch}" |\
#    grep -A1 "$fTitle" | grep -m 1 'https://.*\/movie' | tr -d ' ')
#  curlCmd="curl -s -k $urlLink | hxnormalize -l 9999 -x >\"$htmlFile\" 2>&1"
#
#  if [[ -n "$urlLink" ]]; then
#    eval "$curlCmd"
#    meta_title=$(hxselect -ic .title h2 <"$htmlFile" | w3m -dump -T 'text/html')
#    # Using w3m to sanitize output.
#    meta_synopsis=$(hxselect -ic .overview <"$htmlFile" | w3m -dump -cols 9999 -T 'text/html')
#    releaseDate=$(hxselect -c .releases li <"$htmlFile" |\
#      sed 's/<img.*\/img>//' | w3m -dump -T 'text/html' | head -n 1)
#    meta_date=$(date -d "$releaseDate" +%m/%d/%Y)
#    #rm "$htmlFile"
#  fi
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

  #echo -e "\n   ${C3}urlLink: ${C7}$urlLink${C0}"
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

  ## Set frame rate if not resized.
  #shellcheck disable=SC2154
  if [[ $(echo "$vFPS >= $target_FPS" |bc -l) ]]; then
    FPS=$target_FPS
  else
    FPS=$vFPS
  fi

  #TEMP Testing
  FPS="24000/1001"

  # Check if video resize is enabled (default).
  if [[ $vResize != 'true' ]]; then
    traceIt $LINENO setOpts " info " "Skipping video resize due to override."
  else
    # Resize video if larger than 1280x720 or smaller than 720x400
    if (( vWidth > 1280 )); then
      vOpts="scale=1280:-2,fps=fps=$FPS"
      scale=$(echo "scale=6; (1280/$vWidth)" | bc)
    elif (( vWidth < 720 )); then
      vOpts="scale=720:-2,fps=fps=$FPS"
      scale=$(echo "scale=6; (720/$vWidth)" | bc)
    else
      vOpts="fps=fps=$FPS"
      scale=1
    fi
  fi
  traceIt $LINENO setOpts " info " "scale=$scale"

  _vSize=$(printf "%.0f" "$(echo "scale=2; $vHeight*$scale" | bc)")
  #shellcheck disable=SC2154
  _hSize=$(printf "%.0f" "$(echo "scale=2; $vWidth*$scale" | bc)")
  ## Determine target bit rate to yield desired Qf
  traceIt $LINENO setOpts " info " "target_QF=$target_QF"
  traceIt $LINENO setOpts " info " "_hSize=$_hSize"
  traceIt $LINENO setOpts " info " "_vSize=$_vSize"
  traceIt $LINENO setOpts " info " "FPS=$FPS"
  target_vBitrate=$(printf "%.0f" "$(echo "scale=2; ($target_QF*$_hSize*$_vSize*$FPS)/1000" | bc)")
  traceIt $LINENO setOpts " info " "target_vBitrate=${target_vBitrate}k"
  
  # This can be used to blur logo maps.
  # Filter logo if bitmap detected.
  if [[ -e "${inDir}/${baseName[$l]}.png" ]]; then
    # shellcheck disable=SC2089
    vOpts="${vOpts},removelogo=\"${inDir}/${baseName[$l]}.png\""
  fi
  traceIt $LINENO setOpts " info " "vOpts=$vOpts"

  ## Build video codec arguments
  # EXAMPLE: videoOpts="-c:v libx264 -crf $CRF -preset $vPreset -tune $vTune \
  #          -refs 3 -maxrate $maxBitrate -bufsize $bufSize $vExtra"
  videoOpts="-c:v libx264"
  #videoOpts="$videoOpts -crf $CRF"
  videoOpts="$videoOpts -b:v ${target_vBitrate}k"
  videoOpts="$videoOpts -preset $vPreset"
  videoOpts="$videoOpts -tune $vTune"
#  if [[ -n $vExtra ]]; then
#    videoOpts="$videoOpts $vExtra"
#  fi
  traceIt $LINENO setOpts " info " "videoOpts=$videoOpts"
  vStream="0:$mainVideo"
  
  ## Build audo codec arguments
  traceIt $LINENO setOpts " info " "aOpts=$aOpts"

  audioOpts="-c:a libfdk_aac"
  audioOpts="$audioOpts -b:a ${target_aBitrate}k"
  if [[ $aRemix != 'true' ]]; then
    audioOpts="$audioOpts -ac $aChannels"
  else
    audioOpts="$audioOpts -ac 2"
  fi
  if [[ -n $aOpts ]]; then
    audioOpts="$audioOpts -ar 48k"
  fi
  traceIt $LINENO setOpts " info " "audioOpts=$audioOpts"
  aStream="0:$mainAudio"

  ## Build subtitle options
  if [[ -n $sMap ]]; then
    subOpts="-c:s mov_text -metadata:s:s:0 language=eng"
  else
    subOpts="-sn"
  fi
  traceIt $LINENO setOpts " info " "subOpts=$subOpts"

  ## Create complex filters
  if [[ -n $aOpts ]]; then
    complexOpts="[$vStream]${vOpts}[vOut];[$aStream]${aOpts}[aOut]"
    vMap="-map [vOut]"
    aMap="-map [aOut]"
  else
    complexOpts="[$vStream]${vOpts}[vOut]"
    vMap="-map [vOut]"
    aMap="-map 0:$mainAudio"
  fi
  traceIt $LINENO setOpts " info " "complexOpts=$complexOpts"

#  ## Build final map
#  streamMap="$vMap $aMap $sMap"
#  traceIt $LINENO setOpts " info " "streamMap=$streamMap"

  # Check for no audio
  if [[ $noAudio -eq 1 ]]; then
    audioOpts="-an"
    aMap=""
  fi

  encodeOpts="$videoOpts $vMap $audioOpts $aMap $subOpts $sMap"
  traceIt $LINENO setOpts " info " "encodeOpts=$encodeOpts"

  return 0
}

encodeIt ()
{
  inFile="${fullName[$l]}"
  #_inDir=$(dirname "${fullName[$l]}")

  if [[ ! -d "${outDir[$l]}" ]]; then
    mkdir -p "${outDir[$l]}"
    sudo chown $user:$group "${outDir[$l]}"
    sudo chmod 775 "${outDir[$l]}"
  fi
  if [[ $hq != 1 ]]; then 
    outFile="${outDir[$l]}/${baseName[$l]}.mp4"
    echo -e "         ${C3}Output:${C6} ...${baseDir[$l]}/${baseName[$l]}.mp4${C0}\n"
  else
    outFile="${outDir[$l]}/${baseName[$l]}-∞.mp4"
    echo -e "         ${C3}Output:${C6} ...${baseDir[$l]}/${baseName[$l]}-∞.mp4${C0}\n"
  fi

  tempOut="$tempDir/converting.mp4"

  traceIt $LINENO encdeIt " CMD  " "> ffmpeg -hide_banner -y -loglevel quiet -stats -i \"$inFile\" -i \"$metaFile\" -map_metadata 1 -filter_complex $complexOpts $encodeOpts \"$outFile\""

  echo -e "                                     total time=${C4}$duration${C0}"
  # shellcheck disable=SC2086,SC2090
  ffmpeg -hide_banner -y -loglevel quiet -stats -i "$inFile" \
    -i "$metaFile" -map_metadata 1 -filter_complex "$complexOpts" \
    $encodeOpts "$tempOut" 
  STATUS=$?

  if [[ ! -f "$tempOut" ]]; then
    _override="-c:v libx264 -b:v 1768k -c:a libfdk_aac -b:a 92k -ac 2 -ar 48k -sn"
    logIt "Failed to encode input file, retrying."
    echo -e "                                     total time=${C4}$duration${C0}"
    # shellcheck disable=SC2086,SC2090
    ffmpeg -hide_banner -y -loglevel quiet -stats -i "$inFile" -i "$metaFile" -map_metadata 1 \
      $_override "$tempOut"
    STATUS=$?
  fi

  if (( STATUS > 0 )); then
    logIt "Re-encoding for $inFile failed!"
    traceIt $LINENO encdeIt "ERROR!" "STATUS=$STATUS, ffmpeg failed."
    echo -e "> ${C5}ffmpeg -y -i \"$inFile\" -i \"$metaFile\" -map_metadata 1 -filter_complex $complexOpts $encodeOpts \"$tempOut\"${C0}\n"
  else
    mv -f "$tempOut" "$outFile"
    #!# killWait 0
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

    rm "$metaFile" "$htmlFile" >/dev/null 2>&1
    unset sMap aMap vMap

    {
      mkdir -p "$doneDir/${baseDir[$l]}"
      chgrp -R admins "$doneDir/${baseDir[$l]}"
      mv "${fullName[$l]}" "$doneDir/${baseDir[$l]}/"
    } >> "$traceLog" 2>&1

    logIt "outFile = $outFile"
    # Setting permission on outFile.
    sudo chown $user:$group "$outFile"
    sudo chmod 0664 "$outFile"
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

    --mv
        Will look for music videos in configured directory.

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
#command -v googler >/dev/null 2>&1 || { echo "ERROR: googler is not installed, bailing." >&2; exit 1; }
command -v hxnormalize > /dev/null 2>&1 || { echo "ERROR: html-xml-utils is not installed, bailing." >&2; exit 1; }
command -v w3m > /dev/null 2>&1 || { echo "ERROR: w3m is not installed, bailing." >&2; exit 1; }


###  START OF MAIN  ###
# Check for command line arguments.
if [ "$#" -lt 1 ]; then
  usage
fi

## Get arguments.
# Set Default parameters
vResize='true'
vPreset='medium'
vTune='film'
aRemix='true'
target_QF='.1'
target_aBitrate='160'
target_FPS='23.976'
hq=0
lq=0

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
      hq=1
      shift
      ;;
    --lq)  #Set low quality override
      lq=1
      shift
      ;;
    -m | --movie) #Process movies
      inDir="$searchDir/features"
      shift
      ;;
    --mv) #music video files
      inDir="$searchDir/mtv"
      target_QF=${target_QF:-'.2'}
      target_FPS='30'
      target_aBitrate='192'
      vPreset='slow'
      shift
      ;;
    -o | --other) #Process other videos
      inDir="$searchDir/other"
      shift
      ;;
    -s | --series) #tv series encodes
      inDir="$searchDir/series"
      target_aBitrate='128'
      shift
      ;;
    -v | --video) #video files
      inDir="$searchDir/video"
      target_QF=${target_QF:-'.2'}
      target_FPS='30'
      vResize='false'
      vPreset='slow'
      shift
      ;;
    -x | --restricted) #restriced videos
      inDir="$searchDir/restricted"
      target_aBitrate='92'
      target_QF=${QF:-'.08'}
      vPreset='fast'
      shift
      ;;
    *)  #Unknown option
      echo -e "${C5}ERROR: 10 - Unknown option '$1'${C0}"
      usage
      ;;
  esac
done

if [[ hq -eq 1 ]]; then
  target_QF='.2'
  vResize='false'
  aRemix='false'
  target_aBitrate='192'
  vPreset='slow'
elif [[ lq -eq 1 ]]; then
  target_QF='.08'
  vResize='true'
  aRemix='true'
  target_aBitrate='128'
  vPreset='fast'
fi

# vExtra='profile:v high -level 3.2'

traceIt $LINENO " MAIN  " " info " "*** START OF NEW RUN ***"
echo -e "${C3}\nStarting run of ${C6}Video Converter${C0}"
umask 002

displayIt "Collecting list of files to process"
getFiles
killWait 0

l=0
while (( l < ${#fullName[*]} )) && (( l < 50 )); do
  traceIt $LINENO " MAIN  " " info " "START OF LOOP: $((l+1)) of ${#fullName[*]}"
  traceIt $LINENO " MAIN  " " info " "baseName=${baseName[$l]}"
  echo "" >> $logFile
  logIt "v----------------------------------------------------------v"
  logIt "Start of ${baseName[$l]}"
  logIt "------------------------------------------------------------"
  logIt "inFile=${fullName[$l]}"

  echo -e "\nFile $((l+1)) of $((${#fullName[*]}+1))"
  displayIt "Processing:" "${baseDir[$l]}/${baseName[$l]}"
  probeIt "${fullName[$l]}"
  #cc_probe "${fullName[$l]}"
  ##shellcheck disable=SC1091
  #source .probe.rc
  #probeIt
  #rm .probe.rc
  killWait 0

  displayIt "Normalizing audio track"
  normalizeIt "${fullName[$l]}"
  #shellcheck disable=SC1091
  #source .sample.rc
  #rm .sample.rc
  killWait 0

  displayIt "Setting encode filters"
  setOpts
  killWait 0

  getMeta "${fullName[$l]}"
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
#find "$inDir/" -type d -empty -delete

echo -e "${C3}End of Video Converter run.${C0}"
exit 0
