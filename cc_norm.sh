#!/bin/bash

# Helper script to normalize video/audio file.
# Output ffmpeg -a options.

inFile=$1
ffmpeg_bin=${2:-'/usr/bin/ffmpeg'}
sample=${3:-'-ss 01:00 -t 06:00'}
target_i="-24.0"
target_tp="-2.0"
target_lra="11.0"
outFile="/tmp/sample.json"

ff_string="${ffmpeg_bin} -hide_banner -y"
ff_string+=" ${sample}"
ff_string+=" -i '${inFile}'"
ff_string+=" -vn -sn"
ff_string+=" -filter:a loudnorm="
ff_string+="I=${target_i}:"
ff_string+="tp=${target_tp}:"
ff_string+="LRA=${target_lra}:"
ff_string+="print_format=json"
ff_string+=" -f mp4 /dev/null"

bash -c "$ff_string" 2>&1 | sed -n '/{/,/}/p' > "$outFile"
STATUS=$?

if (( STATUS > 0 )); then
  exit $STATUS
fi

measured_i=$(jq -r .input_i < "$outFile")
measured_tp=$(jq -r .input_tp < "$outFile")
measured_lra=$(jq -r .input_lra < "$outFile")
measured_thresh=$(jq -r .input_thresh < "$outFile")
measured_offset=$(jq -r .target_offset < "$outFile")

loudnorm_string+="-filter:a loudnorm="
loudnorm_string+="print_format=summary:"
loudnorm_string+="linear=true:"
loudnorm_string+="I=${target_i}:"
loudnorm_string+="tp=${target_tp}:"
loudnorm_string+="LRA=${target_lra}:"
loudnorm_string+="measured_I=${measured_i}:"
loudnorm_string+="measured_tp=${measured_tp}:"
loudnorm_string+="measured_LRA=${measured_lra}:"
loudnorm_string+="measured_thresh=${measured_thresh}:"
loudnorm_string+="offset=${measured_offset}"

echo "$loudnorm_string"
rm "$outFile"
exit $STATUS