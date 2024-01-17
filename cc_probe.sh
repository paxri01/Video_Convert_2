#!/bin/bash

inFile="$1"
probeFile=$(mktemp)

if [[ $# -lt 1 ]] || [[ ! -f $inFile ]]; then
  echo "Must specify an existing input file, bailing."
  exit 2
fi

ffprobe -hide_banner -show_entries streams -sexagesimal -of flat "$inFile" > "$probeFile" 2>&1

## Strip unsupported subtitles
sed -i '/^programs\./d' "$probeFile"

## Collect number of streams
mapfile -t streams < <(grep -E '^streams\..*codec_type' "$probeFile")

## Display streams
#grep 'Stream' "$probeFile"

## Process individual streams
i=0
while (( i < ${#streams[*]} )); do
  if grep -q 'video' <<< "${streams[$i]}"; then 
    vDefault=$(grep "streams.stream.${i}\.disposition.default" "$probeFile" | awk -F'=' '{ print $2 }')
    ## Grab default video stream or first if no default.
    if [[ $vDefault -eq 1 || -z $vStream ]]; then
      vStream="0:$i"
      vMap="-map $vStream"
      vCodec=$(grep "streams.stream.${i}\.codec_name" "$probeFile" | awk -F'[""]' '{ print $2 }')
      hSize=$(grep "streams.stream.${i}\.width" "$probeFile" | awk -F'=' '{ print $2 }')
      vSize=$(grep "streams.stream.${i}\.height" "$probeFile" | awk -F'=' '{ print $2 }')
      vFPS=$(grep "streams.stream.${i}\.r_frame_rate" "$probeFile" | awk -F'[""]' '{ print $2 }')
      vFPS=$(echo "scale=4; $vFPS" | bc)
      vBitrate=$(grep 'bitrate' "$probeFile" | sed -n 's/.*bitrate: \([0-9]*\) .*/\1/p')
      vBitrate="$(echo "scale=4; $vBitrate" | bc)"
      mDuration=$(grep 'bitrate' "$probeFile" | awk '{ print $2 }' | tr -d ',')
      vLanguage=$(grep "streams.stream.${i}\..*language" "$probeFile" | awk -F'[""]' '{ print $2 }')
      mainVideo="$i"
    fi
  elif grep -q 'audio' <<< "${streams[$i]}"; then
    aDefault=$(grep "streams.stream.${i}\.disposition.default" "$probeFile" | awk -F'=' '{ print $2 }')
    aLanguage=$(grep "streams.stream.${i}\.*language" "$probeFile" | awk -F'[""]' '{ print $2 }')
    ## Collect first audio stream detected (usually main audio)
    if [[ -z $firstAStream ]]; then
      firstAStream="$i"
    fi
    ## Collect first English audio stream detected
    if [[ $aLanguage =~ (eng|en) || -z $firstEngStream ]]; then
      firstEngStream="$i"
    fi
    if [[ $aDefault -eq 1 ]]; then
      defaultAStream="$i"
    fi
    ## Collect all English audio streams
    if [[ $aLanguage =~ (eng|en) ]]; then
      aStream="0:$i"
      aMap="$aMap -map $aStream"
    fi
  elif grep -q 'subtitle' <<< "${streams[$i]}"; then
    sLanguage=$(grep "streams.stream.${i}\..*language" "$probeFile" | awk -F'[""]' '{ print $2 }')
    if [[ $sLanguage =~ (eng|en) ]]; then
      sCodec_type=$(grep "streams.stream.${i}\.codec_name" "$probeFile" | awk -F'[""]' '{ print $2 }')
      if ! grep -q 'pgs\|dvd_subtitle\|dvb_subtitle' <<< "$sCodec_type"; then
        sStream="0:$i"
        sMap="$sMap -map $sStream"
      fi
    fi
  fi
  ((i++))
done

## Select main audio stream
if [[ $defaultAStream -eq $firstEngStream ]]; then
  mainAStream="$defaultAStream"
elif [[ -n $defaultAStream && -z $firstEngStream ]]; then
  mainAStream="$defaultAStream"
elif [[ -n $firstEngStream ]]; then
  mainAStream="$firstEngStream"
else
  mainAStream="$firstAStream"
fi

if [[ -n $mainAStream ]]; then
  ## Collect default audio stream characteristics
  i="$mainAStream"
  aCodec=$(grep "streams.stream.${i}\.codec_name" "$probeFile" | awk -F'[""]' '{ print $2 }')
  aSamplerate=$(grep "streams.stream.${i}\.sample_rate" "$probeFile" | awk -F'[""]' '{ print $2 }')
  aSamplerate="$(echo "$aSamplerate/1000" | bc)"
  aBitrate=$(grep "streams.stream.${i}\.bit_rate" "$probeFile" | awk -F'[""]' '{ print $2 }')
  ## Convert to kilobits
  aBitrate="$(echo "$aBitrate/1000" | bc)"
  aLanguage=$(grep "streams.stream.${i}\..*language" "$probeFile" | awk -F'[""]' '{ print $2 }')
  aChannels=$(grep "streams.stream.${i}\.channels" "$probeFile" | awk -F'=' '{ print $2 }')
  if [[ -z $aMap ]]; then
    aMap="-map 0:$mainAStream"
  fi
fi

vQF=$(mediainfo "$inFile" | grep 'Bits' | awk '{ print $3 }')
fSize=$(mediainfo "$inFile" | grep 'File size' | awk -F': ' '{ print $2 }')
## Remove leading spaces
#aMap=$(sed 's/^ *//' <<< "$aMap")
aMap=${aMap# }
#sMap=$(sed 's/^ *//' <<< "$sMap")
sMap=${sMap# }

cat << EOF > .probe.rc
fName="$inFile"
fSize="$fSize"
duration="$mDuration"
## VIDEO
vWidth=$hSize
vHeight=$vSize
vBitrate=$vBitrate
vCodec="$vCodec"
vFPS=$vFPS
vLanguage="$vLanguage"
vMap="$vMap"
mainVideo=$mainVideo
vQF=$vQF
## AUDIO (Main)
aBitrate=$aBitrate
aChannels=$aChannels
aCodec="$aCodec"
aLanguage="$aLanguage"
aMap="$aMap"
aSamplerate=$aSamplerate
mainAudio=$mainAStream
## SUBTITLES
sMap="$sMap"
EOF

rm "$probeFile"

