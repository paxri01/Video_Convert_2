# Video_Convert_2

This script will search for video files in various directories as specified by the command line arguments.
The script builds an array of incoming files and then probes the file and will convert each to the specified
format base on the command line arguments.

The main goal of this is to re-encode various video files to play on ANY DLNA device without having to transcode it.  With the default settings in the script, any Smart TV should be able to decode the outputted videos.

Expected incoming directory structure:

    renamed/                            <-- This is the search directory.
    ├── features
    ├── mtv
    ├── restricted
    ├── series                          <-- This is the search directory with subdirectories for each series.
    │   ├── Agatha Christies Poirot 
    │   ├── FantomWorks
    │   ├── Reacher
    │   ├── The Curse of Oak Island
    │   └── Undercover Billionaire
    ├── video

The output directory structure will be duplicated from the search directory structure.
Starting at $videoDir base.

    NAME
      vc2.sh - video converter
  
    SYNOPSIS
      vc2.sh [OPTION]
  
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
  
  EXAMPLE:  
      The following would search for movie files and re-encode them at high quality.

      vc2.sh -m --hq

## Requirements

These are some of the requirements for this script.
* The default audio codec is `libfdk_aac`, your ffmpeg binary must be built with libfdk_aac.
* The default video codec is `libx264`, so, you ffmpeg binary must also be built with x264.
* The following packages are used with this script
  * `ffmpeg`
  * `mediainfo`
  * I'm probably missing other things too and I'm sure someone will let me know.
* And as always, this works fine on my systems ;)

You may change the default codecs, but if you do, you may also need to change the parameters passed to the new codecs.


### Example of output:

Names have been changed to protect the innocent.

    > vc2 -s
    
    Starting run of Video Converter 2
      Collecting list of files to process.........................................................[  OK  ]
    
    File 1 of 16
      Processing: series/TV Show/S02/S02E07.Episode 07............................................[  OK  ]
      Normalizing audio track.....................................................................[  OK  ]
      Setting encode filters......................................................................[  OK  ]
                                           total time=01:27:46.69
    frame=126273 fps=236 q=27.0 Lsize= 1226065kB time=01:27:46.66 bitrate=1907.1kbits/s speed=9.83x    
    ---------------------------
    Orig Size: 1.9G // New Size: 1.2G // File decreased by 35.18%
    ---------------------------
      Done
    
    File 2 of 16
      Processing: series/TV Show/S02/S02E12.Episode 12............................................[  OK  ]
      Normalizing audio track.....................................................................[  OK  ]
      Setting encode filters......................................................................[  OK  ]
                                           total time=01:31:43.42
    frame=131950 fps=232 q=27.0 Lsize= 1282980kB time=01:31:43.38 bitrate=1909.8kbits/s speed=9.67x    
    ---------------------------
    Orig Size: 2.1G // New Size: 1.3G // File decreased by 41.24%
    ---------------------------
      Done


  
\- Cheers,
Rick