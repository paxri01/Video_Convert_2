#!/bin/bash

#outdir=/data2/usenet/renamed/youporn
#inDir=${1:-.} # Default to current directory if no argument is provided
inDir=.
rename=${1:-0}

mapfile -t inFiles < <(find "$inDir" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.wmv" -o -iname "*.webm" \))

cleanup()
{
  inFile=$1
  
  # Validate input file exists
  if [[ ! -f "$inFile" ]]; then
    echo "Error: File '$inFile' not found" >&2
    return 1
  fi
  outFile=$(basename "$inFile" | sed 's/ /\./g' | tr '[:upper:]' '[:lower:]')
  ext=${inFile##*.}

  outFile=${outFile//60fps./}
  outFile=${outFile//../.}

  check="$(sed -rn "s/.*(\.-\..*)\.${ext}$/\1/p" <<< "$outFile")"
  check=${check/#\.-\./}
  check="${check//\.-\./}"

  # Check file source
  if grep -q '.-.ince' <<< "$outFile"; then
    source="(incestflix) "
    outFile="$(sed -rn 's/(.*)\.-\.ince.*/\1/p' <<< "$outFile").${ext}"
  elif grep -q 'beeg' <<< "$outFile"; then
    source="(beeg) "
    outFile="$(sed -rn 's/(.*)\.beeg.*/\1/p' <<< "$outFile").${ext}"
  elif grep -q 'youporn' <<< "$outFile"; then
    source="(youporn) "
    outFile="$(sed -rn 's/(.*)\.-\.youporn.*/\1/p' <<< "$outFile").${ext}"
  elif grep -q 'redtube' <<< "$outFile"; then
    source="(redtube) "
    outFile="$(sed -rn 's/(.*)\.-\.redtube.*/\1/p' <<< "$outFile").${ext}"
  elif grep -q 'pornhub' <<< "$outFile"; then
    source="(pornhub) "
    outFile="$(sed -rn 's/(.*)\.-\.pornhub.*/\1/p' <<< "$outFile").${ext}"
  elif grep -q '.-.free.sex' <<< "$outFile"; then
    source=""
    outFile="$(sed -rn 's/(.*)\.-\.free.sex.*/\1/p' <<< "$outFile").${ext}"
  else
    printf "[92minFile: %s[0m\n" "$inFile"
    printf "[93mSuffix: %s[0m\n" "$check"

    if [[ -n "$check" ]]; then
      echo -e "Move suffix to prefix? [y/N] \c"
      read -r answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        source="(${check/\.*/}) "
        outFile="$(sed -rn 's/(.*)\.-\..*/\1/p' <<< "$outFile").${ext}"
      else
        echo -e "Trim suffix? [y/N] \c"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
          outFile="$(sed -rn 's/(.*)\.-\..*/\1/p' <<< "$outFile").${ext}"
        else
          source=""
        fi
      fi
    fi
  fi

  outFile="${source}${outFile}"
  printf "inFile: [91m%s[0m\n  outFile: [92m%s[0m\n check: [93m%s[0m\n" \
    "$(basename "$inFile")" "$outFile" "$check"
  if (( rename != 0 )); then
    # Check if output file already exists
    if [[ -f "$outFile" ]]; then
      echo "Warning: Output file '$outFile' already exists, skipping" >&2
      return 1
    fi
    
    if mv "${inFile}" "${outFile}"; then
      echo "Successfully renamed to: $outFile"
    else
      echo "Error: Failed to rename '$inFile' to '$outFile'" >&2
      return 1
    fi
  else
    echo -e "mv [93m${inFile}[0m ->\n  [91m${outFile}[0m\n"
  fi
}

# MAIN
i=0
while (( i < ${#inFiles[*]} )); do
  cleanup "${inFiles[$i]}"
  ((i++))
done

