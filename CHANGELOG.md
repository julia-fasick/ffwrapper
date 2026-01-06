# Changelog

## 01.05.2026

- fixed bug where when fallback bitrate is echod ffmpeg crashes
- created changelog
- using `-r` when `-o` is current extension (i.e., when the output file already exists) will operate in-place. `ffmpeg` will output to `NEW_{existing file name}` then the original file is deleted and the new file moved to the old file name.