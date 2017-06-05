#!/bin/bash

inFile=$1

umask 0022

sed -i "s/^.*$/file \'&\'/" ./cc.lst
ffmpeg -loglevel fatal -y -safe 0 -f concat -i ./cc.lst -c:v copy -c:a copy "$inFile"
