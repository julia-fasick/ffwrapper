# ffwrapper

## Overview
ffwrapper is a small Bash wrapper around `ffmpeg` that makes common video tasks quick and repeatable without memorizing long command lines.

It focuses on two workflows:
- Fast remuxing (copy streams into a new container without re-encoding)
- HEVC (H.265) transcoding using NVIDIA NVENC, with sensible, auto-derived bitrates and optional 10‑bit output

Additionally, you can regenerate timestamps for glitchy sources and batch-process an entire directory.

## Requirements
- `ffmpeg` and `ffprobe` available on PATH
- For HEVC transcoding: an NVIDIA GPU with NVENC support and ffmpeg built with `hevc_nvenc`
- Supported input containers: `.mp4`, `.mkv`, `.m4v`, `.mov` (directory mode filters by these)
- Supported output containers: `mp4`, `mkv`, `srt`, `ass`

Note: Transcoding (`-t`) is only allowed when output (`-o`) is `mp4` or `mkv`.

## Installation
- Option A: Use directly from this repo
  - `chmod +x ffwrapper.sh`
  - Run with `./ffwrapper.sh`
- Option B: Put it somewhere on your PATH
  - `cp ffwrapper.sh /usr/local/bin/ffwrapper`
  - `chmod +x /usr/local/bin/ffwrapper`
  - Run with `ffwrapper`
- Option C:
  - Option B, but use a symlink to wherever the repo was cloned. This allows for easy updates via `git pull`.

## Usage
Synopsis:
  `ffwrapper.sh (-i [input_file] | -d [directory]) -s [comma_list] -o [output_format] [-t] [-b] [-g] [-r]`

Key behavior:
- Exactly one of `-i` or `-d` is required.
- `-s` and `-o` are required.
- If an output file with the same name already exists in the target directory, `NEW_` is prefixed to the output filename.
- When `-r` is used and `NEW_` was added, the script will remove the source and then rename the `NEW_` file to the original name.

### Options
- `-h`  Show help and exit.
- `-i`  Input file path. Use this for single-file mode. Mutually exclusive with `-d`.
- `-d`  Input directory. Processes all files matching: `.mkv`, `.mp4`, `.m4v`, `.mov`. Mutually exclusive with `-i`.
- `-s`  Select streams to include in the output, as a comma-separated list of zero-based stream indices. Example: `-s 0,2,5`
      Use `ffprobe` to inspect streams and decide which to keep. All non-selected streams are excluded.
- `-o`  Output container/format. One of: `mp4`, `mkv`, `srt`, `ass`.
- `-t`  Transcode video to HEVC via NVENC. The script auto-derives a target average bitrate and max bitrate dependent on the original codec.
      Only valid with `-o mp4` or `-o mkv`.
- `-b`  Use 10‑bit video pixel format (`p010le`). Intended for use with `-t`.
- `-g`  Regenerate timing data (adds `-fflags +discardcorrupt +genpts`). Useful when the output looks choppy/laggy, especially from Matroska sources.
- `-r`  Remove the source file after successful completion. Use with caution.

### What ffwrapper does under the hood
- Mapping: For each index in `-s`, the script adds `-map 0:<index>` so only the chosen streams are included.
- Remuxing (no `-t`): Video is copied (`-c:v copy`). Audio is always copied (`-c:a copy`).
- Transcoding (`-t`): Video is encoded with `hevc_nvenc` using a high-quality preset and VBR. Audio is still copied.
- Timing fix (`-g`): Adds flags to discard corrupt packets and regenerate PTS/DTS.
- Output naming: Outfile is `basename(input) + "." + -o format`, created next to the source.

Notes and limitations:
- If `ffprobe` cannot determine the source bitrate, a 5 Mbps fallback is used for auto bitrates. This is rare (never seen in extensive testing), but technically possible.
- `-t` currently uses only `hevc_nvenc`. Other encoders/accelerators are not yet supported.
- For subtitle extraction (`-o srt` or `-o ass`), choose the subtitle stream index with `-s`. Do not use `-t` with subtitle outputs.
  Depending on the source, including non-subtitle streams alongside a subtitle output may fail; prefer selecting only the subtitle stream.

## Examples
1) Remux a single file to MKV, keeping only video stream 0 and the first audio stream 1:
```
./ffwrapper.sh -i "/path/Movie.mp4" -s 0,1 -o mkv
```

2) Transcode a single file to HEVC in MP4 with auto bitrates and 10‑bit output, keeping video 0 and audio 1:
```
./ffwrapper.sh -i "/path/Clip.mov" -s 0,1 -o mp4 -t -b
```

3) Regenerate timestamps during remux from MKV to MP4 (can help choppy playback), keeping streams 0,1,2:
```
./ffwrapper.sh -i "/path/Episode.mkv" -s 0,1,2 -o mp4 -g
```

4) Batch process an entire directory, remuxing every `.mkv`/`.mp4`/`.m4v`/`.mov` to MKV and removing sources on success:
```
./ffwrapper.sh -d "/media/ToProcess" -s 0,1 -o mkv -r
```

5) Batch transcode everything in a directory to HEVC MP4, keeping video 0 and a specific audio stream 2:
```
./ffwrapper.sh -d "/media/Camera" -s 0,2 -o mp4 -t
```

6) For all video files in the current directory, extract a subtitle track as SRT and then transcode to 10bit HEVC MP4, while regenerating DTS and PTS and removing the original source:
```
# First, find the subtitle stream index, e.g., 2
ffprobe -hide_banner -i "/path/episode.mkv"
# Then run:
./ffwrapper.sh -d ./ -s 2 -o srt && ./ffwrapper -d ./ -s 0,1 -o mp4 -r -g -t -b
```

## Tips
- Use `ffprobe` to inspect streams and bitrates:
```
ffprobe -hide_banner -show_streams -show_format "/path/file.mkv"
```
- Stream indices start at 0 and are per-input.
- If output playback looks laggy after remuxing, try adding `-g`.
- When using `-r`, consider testing first without it to confirm the command does what you expect.

## License
Released under GNU GPL v3, see LICENSE for details.