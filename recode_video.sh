#!/bin/bash

## DESCRIPTION:
##        This script is used to re-encode a single video with sane
##        parameters.

inFile=$1
baseName=${inFile%.*}
## Video quality factor (bits/pixel rate)
Qf='.1'
## Audio target levels
norm=0
aTBR=160
targetLevel="I=-24:TP=-1.5:LRA=11"

#set -x
ffp "$inFile"

ffprobe -hide_banner -show_entries streams -sexagesimal -of flat "$inFile" > .probe.txt 2>&1

mapfile -t streams < <(grep 'codec_type' .probe.txt)

i=0
while (( i < ${#streams[*]} )); do
  if grep -q 'video' <<< "${streams[$i]}"; then
    vStream=0:$i
    hSize=$(grep "streams.stream.${i}.width" .probe.txt | awk -F'=' '{ print $2 }')
    vSize=$(grep "streams.stream.${i}.height" .probe.txt | awk -F'=' '{ print $2 }')
    fps=$(grep "streams.stream.${i}.r_frame_rate" .probe.txt | awk -F'[""]' '{ print $2 }')
#    measured_vBR=$(grep 'bitrate' .probe.txt | awk '{ print $6 }')
    duration=$(grep 'bitrate' .probe.txt | awk '{ print $2 }')
  elif grep -q 'audio' <<< "${streams[$i]}"; then
    aLanguage=$(grep "streams.stream.${i}.*language" .probe.txt | awk -F'[""]' '{ print $2 }')
    if [[ $aLanguage =~ (eng|en) ]]; then
      aStream=0:$i
      aMap="$aMap -map $aStream"
#      sampleRate=$(grep "streams.stream.${i}.sample_rate" | awk -F'[""]' '{ print $2 }')
#      aCodec=$(grep "streams.stream.${i}.codec_name" .probe.txt | awk -F'[""]' '{ print $2 }')
#      measured_aBR=$(grep "streams.stream.${i}.bit_rate" .probe.text | awk -F'[""]' '{ print $2 }')
    fi
  elif grep -q 'subrip' <<< "${streams[$i]}"; then
    sLanguage=$(grep "streams.stream.${i}.*language" .probe.txt | awk -F'[""]' '{ print $2 }')
    if [[ $sLanguage =~ (eng|en) ]]; then
      sStream=0:$i
      sMap="$sMap -map $sStream"
    fi
  fi
  ((i++))
done

## If no english audio found, grab the first audio stream found
if [[ -z $aStream ]]; then
  aStream="0:$(grep -m 1 'codec_type="audio"' .probe.txt | awk -F'.' '{ print $3 }')"
fi
rm .probe.txt

## Convert cinematic fps to real number
rFPS="$(echo "scale=4; $fps" | bc)"
## Calculate required frame rate to reach target quality factor (Qf)
vTBR=$(printf "%.0f" "$(echo "scale=2; ($Qf*$hSize*$vSize*$rFPS)/1000" | bc)")

if [[ norm -eq 1 ]]; then
  echo "> Normalizing audio levels"
  echo "ffmpeg -hide_banner -y -i \"$inFile\" -vn -sn -filter:a loudnorm=print_format=json \
    -f mp4 /dev/null 2>&1 | sed -n '/{/,/}/p' > .sample.json"
  ffmpeg -hide_banner -y -i "$inFile" -vn -sn -filter:a loudnorm=print_format=json \
    -f mp4 /dev/null 2>&1 | sed -n '/{/,/}/p' > .sample.json
  
  input_i=$(jq .input_i < .sample.json | tr -d '"')
  input_tp=$(jq .input_tp < .sample.json | tr -d '"')
  input_lra=$(jq .input_lra < .sample.json | tr -d '"')
  input_thresh=$(jq .input_thresh < .sample.json | tr -d '"')
  rm .sample.json
  
  echo "> Input I=$input_i"
  
  aOpts="loudnorm=${targetLevel}:linear=true:measured_I=$input_i:measured_tp=$input_tp:measured_LRA=$input_lra:measured_thresh=$input_thresh"
  complexOpts="-filter_complex [$aStream]${aOpts}[aOut]"
  audioOpts="-c:a libfdk_aac -b:a ${aTBR}k -ar 48k -map [aOut]"
else
  audioOpts="-c:a libfdk_aac -b:a ${aTBR}k -ar 48k -map $aStream"
fi

videoOpts="-c:v libx264 -b:v ${vTBR}k -preset medium -tune film -map $vStream"
if [[ -n $sStream ]]; then
  subOpts="-c:s mov_text -map $sStream"
else
  subOpts="-sn"
fi

#echo "> ffmpeg -hide_banner -y -loglevel quiet -stats -i \"$inFile\" $complexOpts $videoOpts $audioOpts $subOpts ./temp.mp4"
echo "                                                $duration"
#shellcheck disable=SC2086
ffmpeg -hide_banner -y -loglevel quiet -stats -i "$inFile" $complexOpts $videoOpts $audioOpts $subOpts ./temp.mp4

mv -f ./temp.mp4 "${baseName}.mp4"
chown rp01:admins "${baseName}.mp4"
chmod 664 "${baseName}.mp4"

ffp "${baseName}.mp4"

