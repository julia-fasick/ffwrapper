#!/bin/bash

# initialize flags to defaults
TENBIT=0
RARG=0
GARG=0
TFLAG=0
INPLACE_RENAME=0

# TODO: check ffmpeg install status

# TODO: enable double dash arguments like --recursive --delete, etc for a more verbose experience

# TODO: after figuring out how to dynamically check ffmpeg support add support for audio transcoding as well

# TODO: dynamically check available hwaccel to support other gpu sets or fallback to software (probaly do qsv, nvenc, then the amd one (amf or vaapi, i forget), then software)

# TODO: log file? save to os specfic location, maybe /var/log?

# TODO:  could parse some config overrides for selecting encoders from a config file to. essentially defaults to reduce command length

while getopts 'hi:d:s:o:brgt' OP; do
	case "$OP" in
	h)
		echo "USAGE: ffwrapper.sh (-i [input_file] -d [directory]) -s [1,2,3,...] -o [output_format] (-t -b -g -r) ."
		echo "Output files will be named to (basename).(output_format). If this already exists, \"NEW_\" will be added before the file name."
		echo "Current supported input containers:   .mp4, .mkv, m4v, .mov."
		echo "Current support output containers:    .mkv, .mp4, .srt, .ass."
		echo "Full args breakdown:"
		echo "-h      Displays this message and exits."
		echo "-i      Runs command on single file. Next argument should be path to file. Either this or -d is required."
		echo "-d      Runs command on all media files in the directory. Next argument should be path to directory. Either this or -i is required."
		echo "-s      Select streams to add to output file. Find which streams you want to use with ffprobe and input them in a comma seperated list. This argument is required."
		echo "-o      Select the output container. This argument is required."
		echo "-t      Transcode to HEVC. Average bitrate will be selected as 60% of input bitrate. Max bitrate is 75% of original source bitrate. Currently only NVENC is supported."
		echo "-b      Convert to 10-bit video. Should only be used with -t (although this is not dynamically checked yet)."
		echo "-g      Regenerate timing data. Useful if remuxing/transcoding from Matroska files which are less strict about accurate decoding timings. Use this if output looks choppy or laggy."
		echo "-r      Removes the source file when command is complete. Will operate in place when current output filename is the same as old filename. Use with caution!"
		echo "For example, if you want to to select streams 0, 2, and 5, as well as convert to 10-bit HEVC for all files in the current directory and save them in the mp4 container while regenerating the timing data and removing the original file after completion, you can run the following:"
		echo "ffwrapper.sh -d ./ -s 0,2,5 -t -b -g -r -o mp4"
		exit
		;;
	i)
		IARG="$OPTARG"
		;;
	d)
		DARG="$OPTARG"
		;;
	s)
		# save/reset ifs
		OLDIFS="$IFS"
		IFS=',' read -ra SARG <<<"$OPTARG"
		IFS="$OLDIFS"
		;;
	o)
		OARG="$OPTARG"
		;;
	b)
		#TODO: ensure 10bit is only used when reencoding (i.e. with -t)
		#TODO: use different pixel formats based on the encoders to ensure compatibility
		#TODO: verify 10bit capabilities in container and transcoder
		TENBIT=1
		;;
	r)
		RARG=1
		;;
	g)
		GARG=1
		;;
	t)
		TFLAG=1
		;;
	?)
		echo "Unknown option. Run with -h to see help."
		;;
	esac
done

# either -i or -d is required
if [[ -z "$IARG" && -z "$DARG" ]]; then
	echo "ERROR: Either -i or -d needs to be provided!"
	exit 1
fi

# ensure i or d, whichever is provided, is a valid file/directory respectively
if [[ -z "$IARG" ]]; then
	# in directory mode ensure it's valid
	if ! [[ -d "$DARG" ]]; then
		echo "ERROR: $DARG is not a valid directory!"
		exit 1
	fi
else
	# in file mode ensure it's valid
	if ! [[ -f "$IARG" ]]; then
		echo "ERROR: $IARG is not a valid file!"
		exit 1
	fi
fi

# -i and -d cannot be used together
if [[ -n "$IARG" && -n "$DARG" ]]; then
	echo "ERROR: -i and -d options cannot be used together!"
	exit 1
fi

# -s is required, ensure the array has at least one element
if [[ "${#SARG[@]}" -eq 0 ]]; then
	echo "ERROR: -s is required!"
	exit 1
fi

# ensure -s array entries are all numerical options
for s in "${SARG[@]}"; do
	if ! [[ "$s" =~ ^[0-9]+$ ]]; then
		echo "ERROR: Invalid stream index '$s'! All entries passed in with -s must be nonnegative integers."
		exit 1
	fi
done

# -o is required
if [[ -z "$OARG" ]]; then
	echo "ERROR: -o must be provided!"
	exit 1
fi

# ensure -o is valid format (maybe just start with mkv/mp4/srt/ass)
# TODO: dynamically validate by parsing through the output of whatever command show ffmpeg codec support
if [[ "$OARG" != "mp4" && "$OARG" != "mkv" && $OARG != "srt" && "$OARG" != "ass" ]]; then
	echo "ERROR: Invalid output format! If you can ensure another container will be compatible with this program and HEVC content, make a pull request adding it to the above filter (include your testing)."
	exit 1
fi

# TODO: if -t check nvenc support (or better yet, add support for other hardware accelerated (or unacclerated, even) transcoders)
# -2 can only be used if -o is mkv or mp4
# TODO: dynamically validate by parsing through the output of whatever command show ffmpeg codec support
if [[ $TFLAG -eq 1 && "$OARG" != "mp4" && "$OARG" != "mkv" ]]; then
	echo "ERROR: -t can only be used when -o is set to 'mp4' or 'mkv'! If you can ensure another container will be compatible with this program and HEVC content, make a pull request adding it to the above filter (include your testing)."
	exit 1
fi

function run_one() {
	# establish some vars holding info we'll use later
	if [[ -z "$1" ]]; then
		echo "BUG: run_one called with empty argument" >&2
		return 99
	fi
	INPUT="$1"
	OUTDIR=$(dirname "$INPUT")
	BASENAME=$(basename "$INPUT")

	echo "${INPUT}"
	echo "${OUTDIR}"
	echo "${BASENAME}"

	# Build command as an array to avoid shell parsing issues with spaces/parentheses
	local cmd=(ffmpeg -hide_banner)

	if [[ $GARG -eq 1 ]]; then
		cmd+=(-fflags +discardcorrupt -fflags +genpts)
	fi

	# add file to command
	cmd+=(-i "$INPUT")

	# add streams to command
	for s in "${SARG[@]}"; do
		cmd+=(-map "0:${s}")
	done

	# add 10bit format to command
	if [[ $TENBIT -eq 1 ]]; then
		cmd+=(-pix_fmt p010le)
	fi

	# add hevc transcode to command
	if [[ $TFLAG -eq 1 ]]; then
		# we will try to auto calculate new bitrates. start with stream bitrate. mkvs often dont have that, so check that tag if that fails.
		# if still fails try container bitrate. if STILL nothing just use 5 Mbps

		# stream bitrate
		SRC_BITRATE_RAW=$(ffprobe -v error -select_streams v:0 \
			-show_entries stream=bit_rate \
			-of default=noprint_wrappers=1:nokey=1 "$INPUT")

		# matroska bps tag
		if ! [[ "$SRC_BITRATE_RAW" =~ ^[0-9]+$ ]] || [[ "$SRC_BITRATE_RAW" -eq 0 ]]; then
			SRC_BITRATE_RAW=$(ffprobe -v error -select_streams v:0 \
				-show_entries stream_tags=BPS \
				-of default=noprint_wrappers=1:nokey=1 "$INPUT")
		fi

		# container bitrate
		if ! [[ "$SRC_BITRATE_RAW" =~ ^[0-9]+$ ]] || [[ "$SRC_BITRATE_RAW" -eq 0 ]]; then
			SRC_BITRATE_RAW=$(ffprobe -v error \
				-show_entries format=bit_rate \
				-of default=noprint_wrappers=1:nokey=1 "$INPUT")
		fi

		# fallback
		if ! [[ "$SRC_BITRATE_RAW" =~ ^[0-9]+$ ]] || [[ "$SRC_BITRATE_RAW" -eq 0 ]]; then
			echo "WARNING: Bitrate not detected for '$INPUT' (ffprobe returned '$SRC_BITRATE_RAW'). Using fallback 5 Mbps." >&2
			SRC_BITRATE=5000000
		else
			SRC_BITRATE=$SRC_BITRATE_RAW
		fi

		SRC_KBPS=$((SRC_BITRATE / 1000))
		# calculate new hevc bitrates (say 60% avg and 75% max)
		AUTO_BV=$((SRC_KBPS * 60 / 100))
		AUTO_MAXRATE=$((SRC_KBPS * 75 / 100))
		# use new values
		cmd+=(-c:v hevc_nvenc -preset p7 -vtag hvc1 -profile:v main10 -tune:v hq -rc:v vbr -multipass 2 -b:v "${AUTO_BV}k" -maxrate "${AUTO_MAXRATE}k" -spatial-aq 1 -aq-strength 8 -rc-lookahead 32)
	else
		cmd+=(-c:v copy)
	fi

	# add copy audio specifier
	cmd+=(-c:a copy)

	# add output to command
	OUTFILE="${BASENAME%.*}.$OARG"
	if [[ -e "${OUTDIR}/${OUTFILE}" ]]; then
		OUTFILE="NEW_${OUTFILE}"
		INPLACE_RENAME=1 # track so we can rename after rm
	else
		INPLACE_RENAME=0
	fi

	cmd+=("${OUTDIR}/${OUTFILE}")

	# echo command for debug purposes
	printf 'Running: '
	printf '%q ' "${cmd[@]}"
	echo

	# run ffmpeg
	"${cmd[@]}" || return $?

	# handle remove/rename after successful ffmpeg
	if [[ "$RARG" -eq 1 ]]; then
		rm -- "$INPUT"
		if [[ "$INPLACE_RENAME" -eq 1 ]]; then
			mv -- "${OUTDIR}/${OUTFILE}" "$INPUT"
		fi
	fi
}

# if in file mode just run the command
if [[ -n "$IARG" ]]; then
	run_one "$IARG" || exit $?
else
  # get realpath for DARG so that find behaves
  if [[ -n "$DARG" ]]; then
      DARG="$(realpath "$DARG")"
  fi
  shopt -s nullglob
  for FILE in "$DARG"/*.{mkv,mp4,m4v,mov}; do
    [[ -f "$FILE" ]] || continue
    run_one "$FILE" || exit $?
  done
fi
