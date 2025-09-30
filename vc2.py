#!/usr/bin/env python3
"""
Video Converter 2 - Python Version
Re-encodes video files to sane/portable parameters.

This script searches for video files in various directories and converts them
using ffmpeg with optimized settings based on content type.
"""

import argparse
import logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

# ANSI color codes
class Colors:
    GREEN = '\033[38;5;040m'
    GREY = '\033[38;5;243m'
    WHITE = '\033[38;5;254m'
    YELLOW = '\033[38;5;184m'
    RED = '\033[38;5;160m'
    PURPLE = '\033[38;5;165m'
    BLUE = '\033[38;5;063m'
    RESET = '\033[0;00m'

@dataclass
class VideoFile:
    """Represents a video file to be processed"""
    full_path: str
    filename: str
    base_name: str
    extension: str
    base_dir: str
    out_dir: str

@dataclass
class EncodingParams:
    """Encoding parameters for different content types"""
    audio_remix: bool = True
    audio_channels: Optional[int] = None
    target_fps: str = '24000/1001'
    target_qf: float = 0.1
    target_a_bitrate: str = '160k'
    target_sample_rate: str = '48k'
    v_preset: str = 'medium'
    v_resize: bool = True
    v_tune: str = 'film'
    sample_range: str = '-t 15:00'

class VideoConverter:
    """Main video converter class"""
    
    def __init__(self):
        # Display settings
        self.pad_length = 100
        
        # Configuration
        self.ffmpeg_bin = '/usr/local/bin/ffmpeg'
        self.base_dir = '/data2/usenet'
        self.search_dir = f"{self.base_dir}/renamed"
        self.work_dir = f"{self.base_dir}/tmp"
        self.log_dir = '/var/log/convert'
        self.done_dir = f"{self.base_dir}/done"
        self.video_dir = "/video"
        self.temp_dir = "/video/temp"
        self.user = "serviio"
        self.group = "video"
        
        # Default parameters
        self.audio_codec = 'libfdk_aac'
        self.video_codec = 'libx264'
        self.cuda = False
        self.hq = False
        self.lq = False
        
        # Content type parameters
        self.encoding_params = {
            'movie': EncodingParams(
                target_fps='24000/1001',
                target_qf=0.1,
                target_a_bitrate='160k',
                v_preset='medium',
                sample_range='-t 15:00'
            ),
            'mv': EncodingParams(
                audio_channels=2,
                target_fps='30',
                target_qf=0.2,
                target_a_bitrate='192k',
                v_preset='slow'
            ),
            'other': EncodingParams(
                target_fps='24000/1001',
                target_qf=0.1,
                target_a_bitrate='160k',
                v_preset='slow'
            ),
            'series': EncodingParams(
                audio_channels=2,
                target_fps='24000/1001',
                target_qf=0.08,
                target_a_bitrate='128k',
                v_preset='fast'
            ),
            'video': EncodingParams(
                target_fps='30',
                target_qf=0.2,
                target_a_bitrate='192k',
                v_preset='slow',
                v_resize=False
            ),
            'restricted': EncodingParams(
                audio_channels=2,
                target_fps='25',
                target_qf=0.08,
                target_a_bitrate='92k',
                v_preset='fast'
            )
        }
        
        # Logging setup
        self.setup_logging()
        
        # Progress display
        self.spinner_running = False
        self.spinner_thread = None
        
    def setup_logging(self):
        """Setup logging configuration"""
        os.makedirs(self.log_dir, exist_ok=True)
        
        # Main log (file only, no console output during spinners)
        self.logger = logging.getLogger('main')
        self.logger.setLevel(logging.INFO)
        main_handler = logging.FileHandler(f"{self.log_dir}/ccvc.log")
        main_handler.setFormatter(logging.Formatter('%(asctime)s %(message)s', datefmt='%b %d %H:%M:%S'))
        self.logger.addHandler(main_handler)
        # Prevent propagation to root logger to avoid duplicate console output
        self.logger.propagate = False
        
        # Trace log (file only)
        trace_file = f"{self.log_dir}/ccvc_trace_{time.strftime('%Y-%m-%d')}.log"
        self.trace_logger = logging.getLogger('trace')
        self.trace_logger.setLevel(logging.DEBUG)
        trace_handler = logging.FileHandler(trace_file)
        trace_handler.setFormatter(logging.Formatter('%(asctime)s [%(lineno)03d] %(funcName)s: [%(levelname)s] %(message)s'))
        self.trace_logger.addHandler(trace_handler)
        # Prevent propagation to root logger to avoid console output
        self.trace_logger.propagate = False
        
    def error_exit(self, message: str, code: int = 1):
        """Exit with error message"""
        self.logger.error(f"ERROR: {message}")
        sys.exit(code)
        
    def check_dependencies(self):
        """Check if required tools are available"""
        required_tools = [self.ffmpeg_bin, 'cc_probe', 'cc_norm']
        for tool in required_tools:
            if not shutil.which(tool):
                self.error_exit(f"{tool} not found in PATH")
                
    def check_cuda_support(self):
        """Check if CUDA encoders are available"""
        try:
            result = subprocess.run(
                [self.ffmpeg_bin, '-encoders'],
                capture_output=True,
                text=True,
                check=True
            )
            return 'h264_nvenc' in result.stdout
        except subprocess.CalledProcessError:
            return False
            
    def get_files(self, content_type: str) -> List[VideoFile]:
        """Find video files in the specified directory"""
        in_dir = f"{self.search_dir}/{self.get_content_dir(content_type)}"
        
        if not os.path.exists(in_dir):
            self.error_exit(f"Input directory {in_dir} does not exist")
            
        # Video file extensions
        video_extensions = [
            'avi', 'mgp', 'mp4', 'm4v', 'wmv', 'mpg', 'mov', 
            'mkv', 'flv', 'webm', 'ts', 'f4v'
        ]
        
        video_files = []
        for root, dirs, files in os.walk(in_dir):
            # Skip .zzz directories
            dirs[:] = [d for d in dirs if '.zzz' not in d]
            
            for file in files:
                if any(file.lower().endswith(f'.{ext}') for ext in video_extensions):
                    if '.zzz' not in file:
                        full_path = os.path.join(root, file)
                        base_name = os.path.splitext(file)[0]
                        extension = os.path.splitext(file)[1][1:]
                        
                        # Calculate relative directory
                        base_dir = os.path.relpath(root, self.search_dir)
                        out_dir = os.path.join(self.video_dir, base_dir)
                        
                        video_file = VideoFile(
                            full_path=full_path,
                            filename=file,
                            base_name=base_name,
                            extension=extension,
                            base_dir=base_dir,
                            out_dir=out_dir
                        )
                        video_files.append(video_file)
                        
        self.trace_logger.info(f"Found {len(video_files)} files to process")
        return video_files
        
    def get_content_dir(self, content_type: str) -> str:
        """Get directory name for content type"""
        content_dirs = {
            'movie': 'features',
            'mv': 'mtv',
            'other': 'other',
            'series': 'series',
            'video': 'video',
            'restricted': 'restricted'
        }
        return content_dirs.get(content_type, content_type)
        
    def probe_video(self, file_path: str) -> Dict:
        """Probe video file using cc_probe"""
        try:
            subprocess.run(['cc_probe', file_path], check=True, cwd='.')
            
            # Read probe results
            if os.path.exists('.probe.rc'):
                probe_data = {}
                with open('.probe.rc', 'r') as f:
                    for line in f:
                        if '=' in line:
                            key, value = line.strip().split('=', 1)
                            probe_data[key] = value
                os.remove('.probe.rc')
                return probe_data
            else:
                self.error_exit("cc_probe failed to generate .probe.rc file")
                
        except subprocess.CalledProcessError:
            self.error_exit("cc_probe failed")
            
    def normalize_audio(self, file_path: str, sample_range: str) -> str:
        """Get audio normalization parameters"""
        try:
            result = subprocess.run(
                ['cc_norm', file_path, self.ffmpeg_bin, sample_range],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            self.error_exit("cc_norm failed")
            
    def build_video_filter(self, probe_data: Dict, params: EncodingParams) -> Tuple[List[str], str, float, float]:
        """Build video filter arguments"""
        v_width = int(probe_data.get('vWidth', '0'))
        v_fps = float(probe_data.get('vFPS', '0'))
        v_map = probe_data.get('vMap', '')
        
        # Parse the vMap to get the map argument (e.g., "-map 0:0")
        v_map_args = []
        if v_map:
            # Handle different vMap formats from cc_probe
            v_map_clean = v_map.strip().strip('"').strip("'")
            if v_map_clean.startswith('-map '):
                # Format: "-map 0:0" -> ['-map', '0:0']
                parts = v_map_clean.split(' ', 1)
                v_map_args = [parts[0], parts[1]] if len(parts) == 2 else []
            elif v_map_clean.startswith('0:'):
                # Format: "0:0" -> ['-map', '0:0']
                v_map_args = ['-map', v_map_clean]
            else:
                # Try to parse as-is
                v_map_args = shlex.split(v_map)
        
        # Build the filter chain
        filter_chain = []
        scale = 1.0
        
        # Resize video if needed
        if params.v_resize:
            if v_width > 1280:
                filter_chain.append("scale=1280:-2")
                scale = 1280 / v_width
            elif v_width < 720:
                filter_chain.append("scale=720:-2")
                scale = 720 / v_width
                
        # Set FPS
        if '/' in params.target_fps:
            fps_parts = params.target_fps.split('/')
            target_fps = float(fps_parts[0]) / float(fps_parts[1])
        else:
            target_fps = float(params.target_fps)
        fps = target_fps if v_fps >= target_fps else v_fps
        filter_chain.append(f"fps=fps={fps}")
        
        # Combine filter chain
        filter_string = ",".join(filter_chain)
        
        return v_map_args, filter_string, scale, fps
        
    def build_video_opts(self, probe_data: Dict, params: EncodingParams, scale: float, fps: float) -> str:
        """Build video encoding options"""
        v_width = int(probe_data.get('vWidth', '0'))
        v_height = int(probe_data.get('vHeight', '0'))
        
        # Calculate video bitrate
        scaled_height = int(v_height * scale)
        scaled_width = int(v_width * scale)
        target_v_bitrate = int((params.target_qf * scaled_width * scaled_height * fps) / 1000)
        
        v_opts = f"-c:v {self.video_codec} -b:v {target_v_bitrate}k "
        
        # Add codec-specific options
        if 'nvenc' in self.video_codec:
            # CUDA encoder options (updated syntax)
            v_opts += f"-preset {params.v_preset} "
            v_opts += "-rc vbr "
            v_opts += "-cq 28 "
            v_opts += "-qmin 0 "
            v_opts += "-qmax 51 "
            v_opts += f"-bufsize {target_v_bitrate * 2}k "
            v_opts += f"-maxrate {target_v_bitrate + target_v_bitrate//2}k "
            v_opts += "-multipass 2"
        else:
            # CPU encoder options
            v_opts += f"-preset {params.v_preset} "
            v_opts += f"-tune {params.v_tune}"
            
        return v_opts
        
    def build_audio_opts(self, probe_data: Dict, params: EncodingParams, normalize: str) -> Tuple[str, List[str]]:
        """Build audio encoding options"""
        a_map = probe_data.get('aMap', '')
        a_channels = probe_data.get('aChannels', '2')
        
        if a_map:
            # Parse audio map arguments
            a_map_args = []
            a_map_clean = a_map.strip().strip('"').strip("'")
            if a_map_clean.startswith('-map '):
                # Format: "-map 0:1" -> ['-map', '0:1']
                parts = a_map_clean.split(' ', 1)
                a_map_args = [parts[0], parts[1]] if len(parts) == 2 else []
            elif a_map_clean.startswith('0:'):
                # Format: "0:1" -> ['-map', '0:1']
                a_map_args = ['-map', a_map_clean]
            else:
                # Try to parse as-is
                a_map_args = shlex.split(a_map)
            
            # Build audio filter arguments
            a_filter_args = []
            if normalize:
                # normalize already contains '-filter:a' so parse it directly
                a_filter_args.extend(shlex.split(normalize))
                
            a_opts = f"-c:a {self.audio_codec} "
            a_opts += f"-b:a {params.target_a_bitrate} "
            
            if not params.audio_remix:
                a_opts += "-ac 2 "
            else:
                channels = params.audio_channels or int(a_channels)
                a_opts += f"-ac {channels} "
                
            a_opts += f"-ar {params.target_sample_rate}"
            return a_opts, a_map_args + a_filter_args
        else:
            return "-an", []
            
    def build_subtitle_opts(self, probe_data: Dict) -> Tuple[str, List[str]]:
        """Build subtitle options"""
        s_map = probe_data.get('sMap', '')
        
        if s_map:
            s_opts = "-c:s mov_text -metadata:s:s:0 language=eng"
            # Parse subtitle map arguments
            s_map_args = []
            s_map_clean = s_map.strip().strip('"').strip("'")
            if s_map_clean.startswith('-map '):
                # Format: "-map 0:2" -> ['-map', '0:2']
                parts = s_map_clean.split(' ', 1)
                s_map_args = [parts[0], parts[1]] if len(parts) == 2 else []
            elif s_map_clean.startswith('0:'):
                # Format: "0:2" -> ['-map', '0:2']
                s_map_args = ['-map', s_map_clean]
            else:
                # Try to parse as-is
                s_map_args = shlex.split(s_map)
            return s_opts, s_map_args
        else:
            return "-sn", []
            
    def create_metadata(self, base_name: str) -> str:
        """Create metadata file"""
        # Extract title and date
        pattern = r'^(.+\s+)\(([^)]+)\)'
        match = re.match(pattern, base_name)
        
        if match:
            f_title = match.group(1).strip()
            f_date = match.group(2).split()[0]
        else:
            f_title = base_name
            f_date = time.strftime('%Y-%m-%d')
            
        meta_file = os.path.join(self.work_dir, f"{base_name}.meta")
        
        with open(meta_file, 'w') as f:
            f.write(";FFMETADATA1\n")
            f.write(f"title={f_title}\n")
            f.write(f"date={f_date}\n")
            f.write("synopsis=No info\n")
            f.write("composer=the Gh0st\n")
            f.write("comment=Converted with Python VC2\n")
            
        return meta_file
        
    def start_spinner(self, message: str, secondary_text: str = ""):
        """Start progress spinner"""
        def spinner():
            chars = ['-', '\\', '|', '/']
            i = 0
            while self.spinner_running:
                # Calculate padding like bash version
                if secondary_text:
                    text_len = len(message) + len(secondary_text)
                    display_text = f"  {Colors.GREY}{message}{Colors.BLUE}{secondary_text}{Colors.RESET}"
                else:
                    text_len = len(message)
                    display_text = f"  {Colors.GREY}{message}{Colors.RESET}"
                
                # Calculate dots needed for padding
                dots_needed = self.pad_length - text_len - 6
                if dots_needed < 0:
                    dots_needed = 0
                
                print(f"\r{display_text}{'.' * dots_needed} {chars[i % len(chars)]}", end='', flush=True)
                i += 1
                time.sleep(0.5)
                
        self.spinner_running = True
        self.spinner_thread = threading.Thread(target=spinner)
        self.spinner_thread.start()
        
    def stop_spinner(self, status: str = "OK"):
        """Stop progress spinner"""
        if self.spinner_running:
            self.spinner_running = False
            if self.spinner_thread:
                self.spinner_thread.join()
                
            status_colors = {
                "OK": Colors.GREEN,
                "ERROR": Colors.RED,
                "WARN": Colors.YELLOW
            }
            color = status_colors.get(status, Colors.PURPLE)
            
            # Clear line and show final status
            dots_needed = self.pad_length - 6
            print(f"\r  {'.' * dots_needed} [{color}{status:^5}{Colors.RESET}]")
            
    def encode_video(self, video_file: VideoFile, content_type: str) -> bool:
        """Encode a single video file"""
        params = self.encoding_params[content_type]
        
        # Create output directory
        if not os.path.exists(video_file.out_dir):
            try:
                subprocess.run(['sudo', 'mkdir', '-p', video_file.out_dir], check=True)
                subprocess.run(['sudo', 'chown', f'{self.user}:{self.group}', video_file.out_dir], check=True)
                subprocess.run(['sudo', 'chmod', '0775', video_file.out_dir], check=True)
            except subprocess.CalledProcessError as e:
                self.error_exit(f"Could not create directory {video_file.out_dir}: {e}")
        
        # Set output filename
        suffix = "-∞" if self.hq else ""
        out_file = os.path.join(video_file.out_dir, f"{video_file.base_name}{suffix}.mp4")
        
        # Probe video
        self.start_spinner("Probing video")
        probe_data = self.probe_video(video_file.full_path)
        self.stop_spinner()
        
        # Normalize audio
        self.start_spinner("Normalizing audio")
        normalize = self.normalize_audio(video_file.full_path, params.sample_range)
        self.stop_spinner()
        
        # Build encoding parameters
        self.start_spinner("Building encode parameters")
        v_map_args, v_filter_string, scale, fps = self.build_video_filter(probe_data, params)
        v_opts = self.build_video_opts(probe_data, params, scale, fps)
        a_opts, a_map_filter_args = self.build_audio_opts(probe_data, params, normalize)
        s_opts, s_map_args = self.build_subtitle_opts(probe_data)
        
        # Create metadata
        meta_file = self.create_metadata(video_file.base_name)
        self.stop_spinner()
        
        # Build ffmpeg command properly without splitting quoted strings
        cmd = [self.ffmpeg_bin, '-hide_banner', '-y', '-loglevel', 'quiet', '-stats']
        
        # Note: Disabled hardware decoding to avoid filter compatibility issues
        # Hardware encoding will still be used via h264_nvenc codec
        # if 'nvenc' in self.video_codec:
        #     cmd.extend(['-hwaccel', 'cuda', '-hwaccel_output_format', 'cuda'])
            
        cmd.extend(['-i', video_file.full_path, '-i', meta_file, '-map_metadata', '1'])
        
        # Add video options
        v_opts_list = self.parse_ffmpeg_args(v_opts)
        cmd.extend(v_opts_list)
        
        # Add video map arguments
        cmd.extend(v_map_args)
        
        # Add video filter
        if v_filter_string:
            cmd.extend(['-vf', v_filter_string])
        
        # Add audio options
        a_opts_list = self.parse_ffmpeg_args(a_opts)
        cmd.extend(a_opts_list)
        
        # Add audio map and filter arguments
        cmd.extend(a_map_filter_args)
            
        # Add subtitle options
        s_opts_list = self.parse_ffmpeg_args(s_opts)
        cmd.extend(s_opts_list)
        
        # Add subtitle map arguments
        cmd.extend(s_map_args)
        
        # Use unique temp filename to avoid conflicts
        temp_filename = f"converting_{uuid.uuid4().hex[:8]}.mp4"
        temp_out = os.path.join(self.temp_dir, temp_filename)
        cmd.append(temp_out)
        
        # Execute encoding
        self.start_spinner(f"Encoding {video_file.filename}")
        duration = probe_data.get('duration', 'unknown')
        print(f"\n                                     total time={Colors.YELLOW}{duration}{Colors.RESET}")
        
        try:
            # Run with visible output for debugging
            cmd_debug = cmd.copy()
            for i, arg in enumerate(cmd_debug):
                if arg == '-loglevel':
                    cmd_debug[i+1] = 'error'
                elif arg == '-stats':
                    pass  # Keep stats for progress
            
            result = subprocess.run(cmd_debug, capture_output=True, text=True, check=True)
            if result.stderr:
                self.trace_logger.info(f"FFmpeg stderr: {result.stderr}")
                
        except subprocess.CalledProcessError as e:
            self.stop_spinner("ERROR")
            # Show more detailed error
            error_msg = f"Encoding failed for {video_file.filename}: {e}"
            if hasattr(e, 'stderr') and e.stderr:
                error_msg += f"\nFFmpeg error: {e.stderr}"
            self.logger.error(error_msg)
            
            # Try to remove incomplete temp file
            if os.path.exists(temp_out):
                try:
                    os.remove(temp_out)
                except:
                    pass
            return False
            
        try:
            self.stop_spinner()
            
            # Move to final location
            subprocess.run(['sudo', 'mv', temp_out, out_file], check=True)
            subprocess.run(['sudo', 'chown', f'{self.user}:{self.group}', out_file], check=True)
            subprocess.run(['sudo', 'chmod', '0664', out_file], check=True)
            
            # Calculate file sizes
            orig_size = os.path.getsize(video_file.full_path)
            new_size = os.path.getsize(out_file)
            
            orig_human = self.format_size(orig_size)
            new_human = self.format_size(new_size)
            
            if new_size < orig_size:
                decrease = ((orig_size - new_size) / orig_size) * 100
                print(f"---------------------------")
                print(f"Orig Size: {orig_human} // New Size: {new_human} // {Colors.GREEN}File decreased by {decrease:.2f}%{Colors.RESET}")
                print(f"---------------------------")
            else:
                increase = ((new_size - orig_size) / orig_size) * 100
                print(f"---------------------------")
                print(f"Orig Size: {orig_human} // New Size: {new_human} // {Colors.RED}File increased by {increase:.2f}%{Colors.RESET}")
                print(f"---------------------------")
                
            # Move original to done directory
            done_path = os.path.join(self.done_dir, video_file.base_dir)
            subprocess.run(['sudo', 'mkdir', '-p', done_path], check=True)
            subprocess.run(['sudo', 'chgrp', '-R', 'admins', done_path], check=True)
            subprocess.run(['mv', video_file.full_path, done_path], check=True)
            
            # Cleanup
            os.remove(meta_file)
            
            self.logger.info(f"Successfully encoded: {out_file}")
            return True
            
        except subprocess.CalledProcessError as e:
            self.stop_spinner("ERROR")
            self.logger.error(f"Encoding failed for {video_file.filename}: {e}")
            return False
            
    def parse_ffmpeg_args(self, args_string: str) -> List[str]:
        """Parse ffmpeg argument string into proper list, handling quotes"""
        try:
            return shlex.split(args_string)
        except ValueError:
            # Fallback to simple split if shlex fails
            return args_string.split()
            
    def format_size(self, size_bytes: int) -> str:
        """Format file size in human readable format"""
        size_float = float(size_bytes)
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_float < 1024.0:
                return f"{size_float:.1f}{unit}"
            size_float /= 1024.0
        return f"{size_float:.1f}PB"
        
    def run(self, content_type: str):
        """Main execution method"""
        print(f"{Colors.WHITE}\nStarting run of {Colors.PURPLE}Video Converter 2 (Python){Colors.RESET}")
        
        # Check dependencies
        self.check_dependencies()
        
        # Setup CUDA if enabled
        if self.cuda:
            if self.check_cuda_support():
                self.video_codec = 'h264_nvenc'
                print(f"{Colors.GREEN}CUDA hardware acceleration enabled{Colors.RESET}")
            else:
                self.error_exit("CUDA hardware encoding not available. Please check NVIDIA drivers and GPU.", 11)
                
        # Apply quality overrides
        if self.hq:
            # High quality overrides (similar to bash version)
            pass
        elif self.lq:
            # Low quality overrides (similar to bash version)
            pass
            
        # Get files to process
        self.start_spinner("Collecting list of files to process")
        video_files = self.get_files(content_type)
        self.stop_spinner()
        
        if not video_files:
            print("No video files found to process")
            return
            
        # Process files (limit to 50 like bash version)
        total_files = min(len(video_files), 50)
        
        for i, video_file in enumerate(video_files[:total_files]):
            print(f"\nFile {i+1} of {total_files}")
            self.start_spinner("Processing: ", f"{video_file.base_dir}/{video_file.base_name}")
            self.stop_spinner()
            
            success = self.encode_video(video_file, content_type)
            
            if success:
                print(f"  {Colors.GREEN}Done{Colors.RESET}")
            else:
                print(f"  {Colors.RED}Failed{Colors.RESET}")
                
def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Re-encodes video files to sane/portable parameters.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -m --hq     Search for movie files and re-encode them at high quality
  %(prog)s -s --cuda   Search for series files and re-encode them using CUDA
        """
    )
    
    # Content type arguments
    content_group = parser.add_mutually_exclusive_group(required=True)
    content_group.add_argument('-m', '--movie', action='store_const', const='movie', dest='content_type',
                              help='Look for feature length movies')
    content_group.add_argument('--mv', action='store_const', const='mv', dest='content_type',
                              help='Look for music videos')
    content_group.add_argument('-o', '--other', action='store_const', const='other', dest='content_type',
                              help='Look for other type video files')
    content_group.add_argument('-s', '--series', action='store_const', const='series', dest='content_type',
                              help='Look for series shows')
    content_group.add_argument('-v', '--video', action='store_const', const='video', dest='content_type',
                              help='Look for video files')
    content_group.add_argument('-x', '--restrict', action='store_const', const='restricted', dest='content_type',
                              help='Look for restricted videos')
    
    # Quality arguments
    parser.add_argument('--hq', action='store_true', help='Re-encode video with high quality settings')
    parser.add_argument('--lq', action='store_true', help='Re-encode video with low quality settings')
    parser.add_argument('--cuda', action='store_true', help='Use NVIDIA CUDA hardware acceleration')
    
    args = parser.parse_args()
    
    # Initialize converter
    converter = VideoConverter()
    converter.hq = args.hq
    converter.lq = args.lq
    converter.cuda = args.cuda
    
    # Run conversion
    try:
        converter.run(args.content_type)
    except KeyboardInterrupt:
        print(f"\n{Colors.RED}Abort detected, stopping now{Colors.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}ERROR: {e}{Colors.RESET}")
        sys.exit(1)

if __name__ == '__main__':
    main()