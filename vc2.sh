#!/bin/bash

# This script will search for video files in various directories as specified by the command line arguments.
# The script builds an array of incoming files and then probes the file and will convert it to the specified
# format base on the command line arguments.

# Program settings
  #ffmpeg_bin='/usr/local/bin/ffmpeg'
  ffmpeg_bin='/usr/bin/ffmpeg'
  #sample_range="-t 10:00"
  sample_range="-ss 01:00 -t 06:00"
  baseDir='/data2/usenet'
  searchDir="$baseDir/renamed"
  workDir="$baseDir/tmp"
  inFiles="$workDir/inFiles.lst"
  logDir='/var/log/convert'
  logFile="$logDir/ccvc.log"
  traceLog="$logDir/ccvc_trace_$(date +%F).log"
  doneDir="$baseDir/done"
  videoDir="/video"
  tempDir="/video/temp"
  user="serviio"
  group="video"

  # Default video parameters
  audio_codec='libfdk_aac'
  video_codec='libx264'
  hq='false'
  lq='false'

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
          Will look for feature length movies in configured directory.
  
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
        shift
        ;;
      --lq)  #Set low quality override
        lq='true'
        shift
        ;;
      -m | --movie) #Process movies
        aRemix='true'
        inDir="$searchDir/features"
        sample_range='-t 15:00'  # 15 minute sample range from beginning
        target_FPS='23.976'
        target_QF='.1'
        target_aBitrate='160k'
        target_sampleRate='48k'
        vPreset='medium'
        vResize='true'
        vTune='film'
        shift
        ;;
      --mv) #music video files
        aRemix='true'
        inDir="$searchDir/mtv"
        target_FPS='30'
        target_QF='.2'
        target_aBitrate='192k'
        target_sampleRate='48k'
        vPreset='slow'
        vResize='true'
        vTune='film'
        shift
        ;;
      -o | --other) #Process other videos
        aRemix='true'
        inDir="$searchDir/other"
        target_FPS='23.976'
        target_QF='.1'
        target_aBitrate='160k'
        target_sampleRate='48k'
        vPreset='slow'
        vResize='true'
        vTune='film'
        shift
        ;;
      -s | --series) #tv series encodes
        aRemix='true'
        inDir="$searchDir/series"
        target_FPS='23.976'
        target_QF='.08'
        target_aBitrate='128k'
        target_sampleRate='48k'
        vPreset='fast'
        vResize='true'
        vTune='film'
        shift
        ;;
      -v | --video) #video files
        aRemix='true'
        inDir="$searchDir/video"
        target_FPS='30'
        target_QF='.2'
        target_aBitrate='192k'
        target_sampleRate='48k'
        vPreset='slow'
        vResize='false'
        shift
        ;;
      -x | --restricted) #restricted videos
        aRemix='true'
        inDir="$searchDir/restricted"
        target_FPS='25'
        target_QF='.08'
        target_aBitrate='92k'
        vPreset='fast'
        vResize='true'
        vTune='film'
        shift
        ;;
      *)  #Unknown option
        echo -e "${CRED}ERROR: 10 - Unknown option '$1'${CNORM}"
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
  CGRN='\033[38;5;040m'  # Green
  CGRY='\033[38;5;243m'  # Grey
  CWHT='\033[38;5;254m'  # White
  CYEL='\033[38;5;184m'  # Yellow
  CRED='\033[38;5;160m'  # Red
  CPUR='\033[38;5;165m'  # Purple
  CBLU='\033[38;5;063m'  # Blue
  CDGR='\033[38;5;234m'  # Dark
  CNORM='\033[0;00m'      # Reset

# Define Global variables
typeset baseName outFile vOpts vFilter aOpts aFilter sOpts fullName fileName extension metaFile

## Defined Functions
  logIt ()
  {
    echo "$(date '+%b %d %H:%M:%S') $1" >> "$logFile"
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
      printf "  ${CGRY}$Text1${CNORM} ${CBLU}$Text2${CNORM}"  
      printf '%*.*s' 0 $((padlength-${#Text1}-${#Text2}-10 )) "$pad"
    else
      # shellcheck disable=SC2059
      printf "  ${CGRY}${Text1}${CNORM}"
      printf '%*.*s' 0 $((padlength - ${#Text1} - 6 )) "$pad"
    fi
  
    rotate &
    rPID=$!
    sleep 1
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
      fullName[i]="$LINE"
      fileName[i]=$(basename "${fullName[$i]}")
      # Strip search directory from base directory.
      baseDir[i]=$(dirname "${fullName[$i]}" | sed -e "s@$searchDir/@@")
      tempFile="${fileName[$i]}"
      extension[i]="${tempFile##*.}"
      baseName[i]="${tempFile%.*}"
      outDir[i]="$videoDir/${baseDir[$i]}"
  
      traceIt $LINENO getFiles " info " "== Processing file number: [$(printf '%.3d' $fileNo)] =="
      traceIt $LINENO getFiles " info " " fullName: ${fullName[$i]}"
      traceIt $LINENO getFiles " info " "directory: ${baseDir[$i]}"
      traceIt $LINENO getFiles " info " " fileName: ${fileName[$i]}"
      traceIt $LINENO getFiles " info " " baseName: ${baseName[$i]}"
      traceIt $LINENO getFiles " info " "extension: ${extension[$i]}"
      traceIt $LINENO getFiles " info " "   outDir: ${outDir[$i]}"
      ((i++))
    done < $inFiles
  
    rm $inFiles
    return 0
  }

  getMeta ()
  {
    # Metadata 
    inFile=$1
    fTitle=$(awk -F'[()]' '{print $1}' <<< "$inFile")
    fDate=$(awk -F'[()]' '{ print $2 }' <<< "$inFile" | awk '{ print $1 }')
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
  
    normalize=$(cc_norm "$inFile" $ffmpeg_bin "$sample_range")
    traceIt $LINENO normalIt " info " "normalize=$normalize"
  
    return 0
  }

  probeIt ()
  {
    inFile="$1"
  
    echo -e "${CDGR}\ncc_probe \"$inFile\"${CNORM}"
    cc_probe "$inFile"
    # shellcheck disable=SC1091
    source .probe.rc
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

  setOpts ()
  {
    ## Build video filter string
    # shellcheck disable=SC2154 # vMap sourced from probeIt()
    vFilter="$vMap "
    vFilter+='-vf '
  
    # Check if video needs to be resized.
    if [[ $vResize != 'true' ]]; then
      traceIt $LINENO setOpts " info " "Skipping video resize due to override."
    else
      # Resize video based on video width (vWidth sourced from probeIt)
      # shellcheck disable=SC2154  # vWidth sourced from probeIt()
      if (( vWidth > 1280 )); then
        vFilter+="scale=1280:-1,"
        scale=$(echo "scale=6; (1280/$vWidth)" | bc)
      elif (( vWidth < 720  )); then
        vFilter+="scale=720:-1,"
        scale=$(echo "scale=6; (720/$vWidth)" | bc)
      else
        scale=1
      fi
    fi
  
    # Check measured video FPS to targetFPS.
    #shellcheck disable=SC2154  # vFPS sourced from probeIt()
    if [[ $(echo "$vFPS >= $target_FPS" |bc -l) ]]; then
      FPS=$target_FPS
    else
      FPS=$vFPS
    fi
    vFilter+="fps=fps=$FPS"
    # This can be used to blur logo maps.
    if [[ -e $inDir/${baseName[$l]}.png ]]; then
      vFilter+=",removelogo=\"$inDir/${baseName[$l]}.png\""
    fi
    traceIt $LINENO setOpts " info " "vFilter: $vFilter"
  
  
    ##  Build video codec string
    vOpts="-c:v $video_codec "

    # Calculate video bitrate
    #shellcheck disable=SC2154  # vHeight sourced from probeIt()
    _vSize=$(printf "%.0f" "$(echo "scale=2; $vHeight*$scale" | bc)")
    _hSize=$(printf "%.0f" "$(echo "scale=2; $vWidth*$scale" | bc)")
    target_vBitrate=$(printf "%.0f" "$(echo "scale=2; ($target_QF*$_hSize*$_vSize*$FPS)/1000" | bc)")
    traceIt $LINENO setOpts " info " "target_vBitrate=$target_vBitrate"
  
    vOpts+="-b:v ${target_vBitrate}k "
    vOpts+="-preset $vPreset "
    vOpts+="-tune $vTune"
    traceIt $LINENO setOpts " info " "vOpts: $vOpts"
  
    ## Build audio filter string
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
        aOpts+="-ac $aChannels "
      fi
      aOpts+="-ar ${target_sampleRate:-48k}"
    else
      aOpts='-an'
    fi
    traceIt $LINENO setOpts " info " "aOpts: $aOpts"
  
  
    ## Build subtitle codec string
    if [[ -n $sMap ]]; then
      sOpts="-c:s mov_text "
      sOpts+="-metadata:s:s:0 "
      sOpts+="language=eng "
      sOpts+="$sMap"
    else
      sOpts="-sn"
    fi
  
    return 0
  }

  encodeIt ()
  {
    inFile=$1

    if [[ ! -d "${outDir[$l]}" ]]; then
      sudo mkdir -p "${outDir[$l]}"
      sudo chown $user:$group "${outDir[$l]}"
      sudo chmod 0775 "${outDir[$l]}"
    fi
    if [[ $hq != 1 ]]; then
      outFile="${outDir[$l]}/${baseName[$l]}.mp4"
    else
      outFile="${outDir[$l]}/${baseName[$l]}-∞.mp4"
    fi

    #ffmpeg_string="${ffmpeg_bin} "
    ffmpeg_string="ffmpeg "
    ffmpeg_string+="-hide_banner -y "
    ffmpeg_string+="-loglevel quiet -stats "
    ffmpeg_string+="-i \"$inFile\" "
    ffmpeg_string+="-i \"$metaFile\" "
    ffmpeg_string+="-map_metadata 1 "
    ffmpeg_string+="$vOpts "
    ffmpeg_string+="$vFilter "
    ffmpeg_string+="$aOpts "
    ffmpeg_string+="$aFilter "
    ffmpeg_string+="$sOpts "
    tempOut="$tempDir/converting.mp4"
  
    echo -e "\n${CDGR}> $ffmpeg_string $tempOut\n"
    traceIt $LINENO encodeIt "  CMD  " "> $ffmpeg_string $outFile"

    echo -e "                                     total time=${CYEL}$duration${CNORM}"
    bash -c "$ffmpeg_string $tempOut"
    STATUS=$?

    if (( STATUS > 0 )); then
      logIt "Re-encoding of $inFile failed!"
      traceIt $LINENO encodeIt "ERROR!" "STATUS=$STATUS, ffmpeg encode failed."
      echo -e "> ${CRED}$ffmpeg_string $tempOut${CNORM}\n"
    else
      sudo mv -f "$tempOut" "$outFile"
      origSize=$(du -b "$inFile" | cut -f1)
      newSize=$(du -b "$outFile" | cut -f1)
      diff=$(echo "scale=4; (($newSize - $origSize)/$origSize)*100" | bc | sed -r 's/0{2}$//')
      origHuman="$(du -h "$inFile" | cut -f1)"
      newHuman="$(du -h "$outFile" | cut -f1)"
      if (( $(echo "$diff < 0" | bc) )); then
        {
          echo "---------------------------"
          echo -e "Orig Size: $origHuman // New Size: $newHuman // ${CGRN}File decreased by $(echo "- $diff" | bc)%${CNORM}"
          echo "---------------------------"
        } | tee -a "$logFile"
      else
        {
          echo "---------------------------"
          echo -e "Orig Size: $origHuman // New Size: $newHuman // ${CRED}File increased by ${diff}%${CNORM}"
          echo "---------------------------"
        } | tee -a "$logFile"
      fi

      # Cleanup temp files and variables
      rm "$metaFile" >/dev/null 2>&1
      unset sMap aMap vMap

      {
        mkdir -p "$doneDir/${baseDir[$l]}"
        sudo chgrp -R admins "$doneDir/${baseDir[$l]}"
        mv "${fullName[$l]}" "$doneDir/${baseDir[$l]}/"
      } >> "$traceLog" 2>&1

      logIt "outFile = $outFile"
      sudo chown $user:$group "$outFile"
      sudo chmod 0664 "$outFile"
    fi

    return $STATUS
  }




## MAIN
traceIt $LINENO " MAIN  " " info " "*** START OF NEW RUN ***"
echo -e "${CWHT}\nStarting run of ${CPUR}Video Converter 2${CNORM}"
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
  displayIt "Processing: ${baseDir[$l]}/${baseName[$l]}" 
  sleep 1
  probeIt "${fullName[$l]}"
  killWait $?
  
  displayIt "Normalizing audio track"
  normalizeIt "${fullName[$l]}"
  killWait $?

  displayIt "Setting encode filters"
  setOpts 
  killWait $?

  getMeta "${baseName[$l]}"

  encodeIt "${fullName[$l]}"

  logIt "------------------------------------------------------------------"
  logIt "End of ${baseName[$l]}"
  logIt "^----------------------------------------------------------------^"
  traceIt $LINENO " MAIN  " " info " "END OF LOOP: $((l+1))"
  echo "" >> "$traceLog"
  echo -e "  ${CGRN}Done${CNORM}"
  ((l++))
done
