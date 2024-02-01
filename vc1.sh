#!/bin/bash

## DESCRIPTION: This script is used to re-encode a single video.

inFile=$1
baseName=${inFile%.*}

# Hint `ln -s ./cc_probe.sh /usr/local/bin/cc_probe` to make this work
cc_probe "$inFile"
source .probe.rc

vFilter="fps=fps=24000/1001"
if [[ $vWidth -gt 1280 ]]; then
  vFilter+=",scale=1280:-2,"
elif [[ $vWidth -lt 720 ]]; then
  vFilter+=",scale=720:-2,"
fi

# Display the command to be run
cat << EOF 
/usr/local/bin/ffmpeg -hide_banner -y -i "$inFile" \\
  $vMap -c:v libx264 -preset fast -crf 18 -vf "$vFilter" \\
  $aMap -c:a libfdk_aac -b:a 160k "$baseName"_recode.mp4
EOF

/usr/local/bin/ffmpeg -hide_banner -y -i "$inFile" \
  $vMap -c:v libx264 -preset fast -crf 18 -vf "$vFilter" \
  $aMap -c:a libfdk_aac -b:a 160k "$baseName"_recode.mp4

# vim: set syntax=bash:
# vim: set filetype=sh:
# vim: set foldmethod=marker:
# vim: set foldlevel=0:
# vim: set foldcolumn=4:
# vim: set shiftwidth=2:
# vim: set tabstop=2:
# vim: set expandtab:
