#!/bin/bash

## DESCRIPTION: This script is used to re-encode a single video with hardware acceleration.

inFile=$1
baseName=${inFile%.*}
typeset -i vWidth
typeset vMap aMap vFilter hwaccel_args encoder_args

# Check if NVIDIA GPU is available
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
  GPU_AVAILABLE=true
else
  GPU_AVAILABLE=false
fi

# Hint `ln -s ./cc_probe.sh /usr/local/bin/cc_probe` to make this work
cc_probe "$inFile"
# shellcheck disable=SC1091
source .probe.rc

# Set up hardware acceleration based on input codec and GPU availability
if [[ $GPU_AVAILABLE == true ]]; then
  case "$vCodec" in
    h264|avc)
      hwaccel_args="-hwaccel cuda -c:v h264_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    hevc|h265)
      hwaccel_args="-hwaccel cuda -c:v hevc_cuvid"
      encoder_args="-c:v hevc_nvenc -preset fast -cq 18"
      ;;
    av1)
      hwaccel_args="-hwaccel cuda -c:v av1_cuvid"
      encoder_args="-c:v av1_nvenc -preset fast -cq 18"
      ;;
    vp8)
      hwaccel_args="-hwaccel cuda -c:v vp8_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    vp9)
      hwaccel_args="-hwaccel cuda -c:v vp9_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    mpeg1video)
      hwaccel_args="-hwaccel cuda -c:v mpeg1_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    mpeg2video)
      hwaccel_args="-hwaccel cuda -c:v mpeg2_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    mpeg4)
      hwaccel_args="-hwaccel cuda -c:v mpeg4_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    vc1)
      hwaccel_args="-hwaccel cuda -c:v vc1_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    mjpeg)
      hwaccel_args="-hwaccel cuda -c:v mjpeg_cuvid"
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
    *)
      # Fall back to software decoding with hardware encoding
      hwaccel_args=""
      encoder_args="-c:v h264_nvenc -preset fast -cq 18"
      ;;
  esac
  echo "Hardware acceleration enabled: GPU encoding with NVENC"
else
  # Fall back to software encoding
  hwaccel_args=""
  encoder_args="-c:v libx264 -preset fast -crf 18"
  echo "Hardware acceleration not available: Using software encoding"
fi

vFilter="fps=fps=24000/1001"
if [[ $vWidth -gt 1280 ]]; then
  vFilter+=",scale=1280:-2"
elif [[ $vWidth -lt 720 ]]; then
  vFilter+=",scale=720:-2"
fi

# Add hardware scaling if using CUDA
if [[ $GPU_AVAILABLE == true && $hwaccel_args == *"cuda"* ]]; then
  # Use CUDA scaling for better performance
  if [[ $vWidth -gt 1280 ]]; then
    vFilter="fps=fps=24000/1001,scale_cuda=1280:-2"
  elif [[ $vWidth -lt 720 ]]; then
    vFilter="fps=fps=24000/1001,scale_cuda=720:-2"
  else
    vFilter="fps=fps=24000/1001"
  fi
fi

# Display the command to be run
cat << EOF 
/usr/local/bin/ffmpeg -hide_banner -y $hwaccel_args -i "$inFile" \\
  $vMap $encoder_args -vf "$vFilter" \\
  $aMap -c:a libfdk_aac -b:a 160k "$baseName"_recode.mp4
EOF

# Execute the command
/usr/local/bin/ffmpeg -hide_banner -y $hwaccel_args -i "$inFile" \
  $vMap $encoder_args -vf "$vFilter" \
  $aMap -c:a libfdk_aac -b:a 160k "$baseName"_recode.mp4

# Check if encoding was successful
if [[ $? -eq 0 ]]; then
  echo "Encoding completed successfully!"
  echo "Output file: ${baseName}_recode.mp4"
  
  # Optional: Display file size comparison
  if command -v ls &> /dev/null; then
    echo "Original size: $(ls -lh "$inFile" | awk '{print $5}')"
    echo "New size: $(ls -lh "${baseName}_recode.mp4" | awk '{print $5}')"
  fi
else
  echo "Encoding failed with exit code: $?"
  exit 1
fi

# vim: set syntax=bash:
# vim: set filetype=sh:
# vim: set foldmethod=marker:
# vim: set foldlevel=0:
# vim: set foldcolumn=4:
# vim: set shiftwidth=2:
# vim: set tabstop=2:
# vim: set expandtab: