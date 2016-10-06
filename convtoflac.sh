#!/bin/bash

# -----------------------------------------------------------------------------
#
#	App Title:      convtoflac.sh
#	App Version:    2.1.4
#	Author:         Jared Breland <jbreland@legroom.net>
#	Homepage:       http://www.legroom.net/software
#
#	Script Function:
#		Convert losslessly compressed audio file to FLAC format, preserving tags
#		Currently supports FLAC, Monkey's Audio (APE), Shorten, WAV, and WavPack
#
#	Instructions:
#		Ensure that all programs are properly set in "Setup environment"
#
#	Caveats:
#		Transcoded files will retain original file name, but use .flac extension
#		The one exception is for FLAC input files - the original input file will
#			be renamed <name>_old.flac, and the transcoded file will be named
#			<name>.flac.
#
#	Requirements:
#		The following programs must be installed and available
#		sed (http://sed.sourceforge.net/)
#			used to handle case sensitivity and tag processing
#		trash-cli (http://code.google.com/p/trash-cli/))
#			used for moving files to trash rather than deleting
#		flac/metaflac (http://flac.sourceforge.net/)
#			used to create and tag new FLAC files
#		alac (http://craz.net/programs/itunes/alac.html)
#			used to decompress ALAC (Apple Lossles) files
#		mp4info, part of libmp4v2 (http://resare.com/libmp4v2/)
#			used to read tags from ALAC (Apple Lossles) files
#		mac (http://sourceforge.net/projects/mac-port/)
#			used to decompress APE (Monkey's Audio) files
#		apeinfo (http://www.legroom.net/software)
#			used to read tags from APE files
#		shorten (http://etree.org/shnutils/shorten/)
#			used to decompress Shorten files
#		ttaenc (http://www.true-audio.com/)
#			used to decompress TTA (True Audio) files
#		wvunpack (http://www.wavpack.com/)
#			used to decompress WavPack files
#		ffmpeg (http://www.ffmpeg.org/)
#			used to decompress MLP and WMA files
#			optionally used to decompress ALAC, APE, Shorten, and WavPack files
#
#	Please visit the application's homepage for additional information.
#
# -----------------------------------------------------------------------------

# Static variables
readonly VERSION="2.1.4"
readonly PROG=$(basename $0)

# Setup environment
TMP='/tmp'
DELETE=''
OVERWRITE=''
USEFFMPEG=''
COMPRESS=8
THREADS=1
COPYTAGS=1
FILES=()
COLOR='\E[33;40m\033[1m' #comment these out if your term doesn't support colors
COLORWARN='\E[31;40m\033[1m'
IFS='@'

# Function to display usage information
function warning() {
	echo -ne "Usage: $PROG [-h] [-V] [-d|-m|-p] [-f] [-tN] [-n] [-o] [-cN]\n"
	echo -ne "       $(printf "%${#PROG}s") <filename> [<file2> ...]\n"
	echo -ne "Convert losslessly compressed audio files to FLAC format, preserving tags\n"
	echo -ne "\nOptions:\n"
	echo -ne "   -h   Display this help information\n"
	echo -ne "   -V   Display version and exit\n"
	echo -ne "   -d   Delete file after conversion\n"
	echo -ne "   -m   Move file to trash after conversion\n"
	echo -ne "   -p   Prompt to delete file after conversion\n"
	echo -ne "   -f   Use ffmpeg instead of default utilities to decode input files\n"
	echo -ne "        Note: Existing tags will not be copied if ffmpeg is used\n"
	echo -ne "   -tN  Convert N number of files concurrently; default is 1\n"
	echo -ne "   -n   Do not copy existing tags to new FLAC file\n"
	echo -ne "   -o   Overwrite existing output FLAC files\n"
	echo -ne "   -cN  Set FLAC compression level, where N = 0 (fast) - 8 (best); default is 8\n"
	echo -ne "\nSupported input formats:\n"
	echo -ne "   Apple Lossless (.m4a)\n"
	echo -ne "   FLAC (.flac)\n"
	echo -ne "   Monkey's Audio (.ape)\n"
	echo -ne "   Shorten (.shn)\n"
	echo -ne "   True Audio (.tta)\n"
	echo -ne "   WAV (.wav)\n"
	echo -ne "   WavPack (.wv)\n"
	echo -ne "\nSupported ffmpeg-only input formats:\n"
	echo -ne "   Meridian Lossless Packing (.mlp)\n"
	echo -ne "   Windows Media Audio Lossless (.wma)\n"
	exit
}

# Function to display colorized output
function cecho () {
	MESSAGE=${1:-"Error: No message passed"}
	echo -e "${COLOR}${MESSAGE}"
	tput sgr0
}

# Function to display colorized warnings
function cwarn () {
	MESSAGE=${1:-"Error: No message passed"}
	echo -e "${COLORWARN}${MESSAGE}"
	tput sgr0
}

# Function to determine if variable is an integer
function is_int() {
	return $(test "$1" -eq "$1" > /dev/null 2>&1);
}

# Function to check for ffmpeg binary
function ffmpeg_check() {
	FFMPEG=$(which ffmpeg 2>/dev/null)
	if [ ! -e "$FFMPEG" ]; then
		echo "Error: cannot find ffmpeg binary"
		MISSING=true
	fi
}

# Function to verify that necessary support binaries exist
function bincheck() {
	MISSING=''
	case $EXT in
		"ape")
			MAC=$(which mac 2>/dev/null)
			APEINFO=$(which apeinfo 2>/dev/null)
			if [ -n "$USEFFMPEG" ]; then
				ffmpeg_check
			else
				[ ! -e "$MAC" ] && MISSING+='mac, '
				[[ -n "$COPYTAGS" && ! -e "$APEINFO" ]] && MISSING+="apeinfo (optional with '-n'), "
			fi
		;;
		"flac")
			if [ -n "$USEFFMPEG" ]; then
				echo "Warning: ffmpeg is not used for FLAC (.flac) files"
			fi
		;;
		"m4a")
			ALAC=$(which alac 2>/dev/null)
			MP4INFO=$(which mp4info 2>/dev/null)
			if [ -n "$USEFFMPEG" ]; then
				ffmpeg_check
			else
				[ ! -e "$ALAC" ] && MISSING+='alac, '
				[[ -n "$COPYTAGS" && ! -e "$MP4INFO" ]] && MISSING+="mp4info (optional with '-n'), "
			fi
		;;
		"mlp")
			USEFFMPEG=true
			COPYTAGS=''
			ffmpeg_check
		;;
		"shn")
			SHORTEN=$(which shorten 2>/dev/null)
			if [ -n "$USEFFMPEG" ]; then
				ffmpeg_check
			elif [ ! -e "$SHORTEN" ]; then
				MISSING+='shorten, '
			fi
		;;
		"tta")
			TTAENC=$(which ttaenc 2>/dev/null)
			if [ ! -e "$TTAENC" ]; then
				if [ -n "$USEFFMPEG" ]; then
					MISSING+='ttaenc (ffmpeg does not support True Audio (.tta) files), '
				else
					MISSING+='ttaenc, '
				fi
			elif [ -n "$USEFFMPEG" ]; then
				echo "Warning: ffmpeg is not used for True Audio (.tta) files"
			fi
		;;
		"wav")
			if [ -n "$USEFFMPEG" ]; then
				echo "Warning: ffmpeg is not used for WAV (.wav) files"
			fi
		;;
		"wv")
			WVUNPACK=$(which wvunpack 2>/dev/null)
			if [ -n "$USEFFMPEG" ]; then
				ffmpeg_check
			elif [ ! -e "$WVUNPACK" ]; then
				MISSING+='wvunpack, '
			fi
		;;
		"wma")
			USEFFMPEG=true
			COPYTAGS=''
			ffmpeg_check
		;;
	esac
	if [ -n "$MISSING" ]; then
		echo "Error: cannot find the following binaries: ${MISSING%%, }"
		exit
	fi
}

# Function to parse mp4info output to find tags and convert to VORBISCOMMENT
function mp4tags() {
	TAGS2=${TAGS}.alac
	$SED -i "/ \w*: /w${TAGS2}" $TAGS
	$SED -i "s/^ //" $TAGS2
	$SED -i "s/: /=/" $TAGS2
	$SED -i "s/ of [0-9]\+//" $TAGS2
	$SED -i "s/\(.*\)=/\U\1=/" $TAGS2
	$SED -i "s/TRACK=/TRACKNUMBER=/;s/YEAR=/DATE=/;s/COMMENTS=/DESCRIPTION=/;s/DISK=/DISCNUMBER=/" $TAGS2
	mv $TAGS2 $TAGS
}

# Function to parse wvunpack output to find tags and convert to VORBISCOMMENT
function wvtags() {
	TAGS2=${TAGS}.wv
	$SED -i "/ = /w${TAGS2}" $TAGS
	$SED -i "s/ = /=/" $TAGS2
	$SED -i "s/\(.*\)=/\U\1=/" $TAGS2
	$SED -i "s/TRACK=/TRACKNUMBER=/;s/YEAR=/DATE=/;s/COMMENT=/DESCRIPTION=/;s/DISK=/DISCNUMBER=/" $TAGS2
	mv $TAGS2 $TAGS
}

# Function to copy tags for supported formats
function processtags() {
	OUTPUT="\nCopying tags for '$FILE'..."
	TAGS=/tmp/$PROG.$RANDOM.tags
	if [ "$EXT" == "ape" ]; then
		$APEINFO -t "$FILE" >$TAGS
	elif [ "$EXT" == "flac" ]; then
		$METAFLAC --export-tags-to=$TAGS "$FILE"
	elif [ "$EXT" == "m4a" ]; then
		$MP4INFO "$FILE" >$TAGS
		mp4tags
	elif [ "$EXT" == "wv" ]; then
		$WVUNPACK -qss "$FILE" >$TAGS
		wvtags
	else
		OUTPUT+="  tags not supported by for this format\n"
		return
	fi
	if [[ $? -ne 0 || ! -s "$TAGS" ]]; then
		OUTPUT+="\nWarning: tags could not be read from \"$FILE\"\n"
	else
		$METAFLAC --import-tags-from=$TAGS "$NAME.flac"
		if [[ $? -ne 0 ]]; then
			OUTPUT+="\nWarning: tags could not be written to \"$NAME.flac\"\n"
		else
			OUTPUT+="  complete\n"
		fi
	fi
	rm $TAGS
	echo -ne "$OUTPUT"
}

# Function to perform actual transcoding
function transcode() {
	QUIET=''

	# Use ffmpeg, if requested, to decode input
	if [ -n "$USEFFMPEG" ] && [ "$EXT" == "ape" -o "$EXT" == "m4a" -o "$EXT" == "mlp" -o "$EXT" == "shn" -o "$EXT" == "wv" -o "$EXT" == "wma" ]; then

		# If WMA, additionally verify file is lossless before continuing
		if [ $($FFMPEG -i "$FILE" 2>&1 | grep 'Stream.*Audio:' | grep wmalossless | wc -l) -lt 1 ]; then
			cwarn "\nError: \"$FILE\" is a lossy WMA.  This should not be converted to FLAC."
			exit 1
		fi

		WAVENAME="/tmp/$(basename $NAME).wav"
		[ $THREADS -gt 1 ] && QUIET='2>/dev/null'
		[ "$EXT" == "mlp" ] && CODEC='-acodec pcm_s24le' || CODEC=
		eval $FFMPEG -i \"$FILE\" $CODEC -f wav \"$WAVENAME.wav\" $QUIET
		if [ $? -ne 0 ]; then
			cwarn "\nError: \"$FILE\" could not be converted to a FLAC file."
			rm "$WAVENAME.wav"
			exit 1
		fi
		eval $FLAC -$COMPRESS $OVERWRITE -o \"$NAME.flac\" \"$WAVENAME.wav\" $QUIET
		if [ $? -ne 0 ]; then
			cwarn "\nError: \"$FILE\" could not be converted to a FLAC file."
			rm "$WAVENAME.wav"
			exit 1
		fi
		rm "$WAVENAME.wav"

	# Otherwise, use dedicated binaries for decoding
	else

		# Monkey's Audio input
		if [ "$EXT" == "ape" ]; then
			[ $THREADS -gt 1 ] && QUIET='2>/dev/null'
			eval $MAC \"$FILE\" - -d $QUIET | $FLAC -$COMPRESS $OVERWRITE -s -o "$NAME.flac" -

		# FLAC input
		elif [ "$EXT" == "flac" ]; then
			# Original FLAC file needs to be renamed
			if [[ -e "${NAME}_old.flac" ]]; then
				if [ $OVERWRITE ]; then
					mv -i "$FILE" "${NAME}_old.flac"
				else
					echo -e "Error: '${NAME}_old.flac' already exists: could not rename input file"
					exit 1
				fi
			else
				mv -i "$FILE" "${NAME}_old.flac"
			fi
			FILE="${NAME}_old.flac"
			[ $THREADS -gt 1 ] && QUIET='-s'
			$FLAC -d "$FILE" $QUIET -c | $FLAC -$COMPRESS $OVERWRITE -s -o "$NAME.flac" -

		# ALAC input
		elif [ "$EXT" == "m4a" ]; then
			$ALAC -t "$FILE"
			# .m4a is not a unique extension, so first verify the format
			if [ $? -ne 0 ]; then
				echo "ERROR: '$FILE' is not a valid ALAC file"
				exit 1
			fi
			[ $THREADS -gt 1 ] && QUIET='-s'
			$ALAC "$FILE" | $FLAC -$COMPRESS $OVERWRITE $QUIET -o "$NAME.flac" -

		# Shorten input
		elif [ "$EXT" == "shn" ]; then
			[ $THREADS -gt 1 ] && QUIET='-s'
			$SHORTEN -x "$FILE" - | $FLAC -$COMPRESS $OVERWRITE $QUIET -o "$NAME.flac" -

		# True Audio input
		elif [ "$EXT" == "tta" ]; then
			[ $THREADS -gt 1 ] && QUIET='2>/dev/null'
			eval $TTAENC -d -o - \"$FILE\" $QUIET | $FLAC -$COMPRESS $OVERWRITE -s -o "$NAME.flac" -

		# WAVE input
		elif [ "$EXT" == "wav" ]; then
			[ $THREADS -gt 1 ] && QUIET='-s'
			$FLAC -$COMPRESS $OVERWRITE $QUIET -o "$NAME.flac" "$FILE"

		# WavPack input
		elif [ "$EXT" == "wv" ]; then
			[ $THREADS -gt 1 ] && QUIET='-q'
			$WVUNPACK $QUIET "$FILE" -o - | $FLAC -$COMPRESS $OVERWRITE -s -o "$NAME.flac" -
		fi
	fi

	# Abort if transcode failed
	if [ ${PIPESTATUS[0]} -ne 0 ]; then
		cwarn "\nError: \"$FILE\" could not be converted to a FLAC file."
		if [[ "$EXT" == "flac" ]]; then
			cwarn "Restoring _old file to original name.\n"
			mv "$FILE" "$NAME.flac"
		fi
		exit 1
	fi

	# Copy metadata to transcoded file, but not for ffmpeg decoding
	if [ $COPYTAGS ]; then
		processtags
	fi

	# Delete old file if requested
	if [ "$DELETE" == "prompt" ]; then
		echo -ne "\nDelete \"$FILE\"? "
		read -e DELPROMPT
		if [[ "$DELPROMPT" == "y" || "$DELPROMPT" == "Y" ]]; then
			DELETE=force
		fi
	fi
	OUTPUT="\nConversion complete - "
	if [ "$DELETE" == "force" ]; then
		rm "$FILE"
		OUTPUT+="deleted"
	elif [ "$DELETE" == "move" ]; then
		$TPUT "$FILE"
		OUTPUT+="trashed"
	else
		OUTPUT+="kept"
	fi
	OUTPUT+=" \"$FILE\"\n\n"
	echo -ne "$OUTPUT"
}

# Process arguments
if [[ $# -eq 0 ]]; then
	warning
else
	while [ $# -ne 0 ]; do

		# Match known arguments
		if [ "$1" == "-h" ]; then
			warning
		elif [ "$1" == "-V" ]; then
			echo "Version $VERSION"
			exit
		elif [ "$1" == "-d" ]; then
			if [ "$DELETE" == "" ]; then
				DELETE="force"
			else
				echo "Error: Only one deletion option (-d, -m, -p) can be specified)"
				exit
			fi
		elif [ "$1" == "-m" ]; then
			if [ "$DELETE" == "" ]; then
				DELETE="move"
			else
				echo "Error: Only one deletion option (-d, -m, -p) can be specified)"
				exit
			fi
		elif [ "$1" == "-p" ]; then
			if [ $THREADS -gt 1 ]; then
				echo "Error: The -p and -t options cannot be used together"
				exit
			fi
			if [ "$DELETE" == "" ]; then
				DELETE="prompt"
			else
				echo "Error: Only one deletion option (-d, -m, -p) can be specified)"
				exit
			fi
		elif [ "${1:0:2}" == "-c" ]; then
			COMPRESS=${1:2}
			is_int "$COMPRESS"
			if [ $? -ne 0 ] || [ $COMPRESS -lt 0 -o $COMPRESS -gt 8 ]; then
				echo "Error: You must specify a number between 0-8 for compression (-cN)"
				exit
			fi
		elif [ "${1:0:2}" == "-t" ]; then
			PROCS=$(grep -c processor /proc/cpuinfo)
			THREADS=${1:2}
			is_int "$THREADS"
			if [ $? -ne 0 ] || [ $THREADS -lt 1 ]; then
				echo "Error: You must specify the number of threads (-tN)"
				exit
			elif [ ${1:2} -gt $PROCS ]; then
				echo "You specified $THREADS threads, but you only have $PROCS processors."
				echo "Please specify no more than $PROCS threads."
				exit
			elif [ "$DELETE" == "prompt" -a $THREADS -gt 1 ]; then
				echo "Error: The -p and -t options cannot be used together"
				exit
			fi
		elif [ "$1" == "-n" ]; then
			COPYTAGS=''
		elif [ "$1" == "-o" ]; then
			OVERWRITE='-f'
		elif [ "$1" == "-f" ]; then
			USEFFMPEG=true
			COPYTAGS=''

		# Anything that's not a known argument gets treated as a file
		else
			FILES[${#FILES[*]}]=$1
		fi
		shift
	done
fi

# Validate COMPRESS setting
if [[ "$COMPRESS" != [0-8] ]]; then
	echo "Error: FLAC compression level must be between 0 and 8"
	exit
fi

# Define and verify core apps exist
SED=$(which sed 2>/dev/null)
FLAC=$(which flac 2>/dev/null)
METAFLAC=$(which metaflac 2>/dev/null)
TPUT=$(which trash-put 2>/dev/null)
MISSING=''
[ ! -e "$SED" ] && MISSING+='sed, '
[ ! -e "$FLAC" ] && MISSING+='flac, '
[ ! -e "$METAFLAC" ] && MISSING+='metaflac, '
[ "$DELETE" == "move" -a ! -e "$TPUT" ] && MISSING+='trash-put, '
if [ -n "$MISSING" ]; then
	echo "Error: cannot find the following binaries: ${MISSING%%, }"
	exit
fi


# Process each passed file sequentially
for FILE in ${FILES[@]}; do
	# Verify file exists
	if [ ! -e "$FILE" ]; then
		echo "Error: '$FILE' does not exist"
		exit 1
	fi

	# Determine file type and base filename
	NAME=${FILE%.*}
	EXT=$(echo "${FILE##*.}" | $SED 's/\(.*\)/\L\1/')

	# Exit if wrong file passed
	if [[ "$EXT" != "ape" && "$EXT" != "flac" && "$EXT" != "m4a" && "$EXT" != "mlp" && "$EXT" != "shn" && "$EXT" != "tta" && "$EXT" != "wav" && "$EXT" != "wv" && "$EXT" != "wma" ]]; then
		echo "Error: '$FILE' is not a supported input format"
		exit 1
	fi

	# Verify support binaries
	bincheck

	# Transcode file, concurrently up to number of specified threads
	cecho "\nProcessing '$FILE'...\n"
	if [ $(jobs | wc -l) -lt $THREADS ]; then
		transcode &
	fi
	while [ $(jobs | wc -l) -ge $THREADS ]; do
		sleep 0.1
		jobs >/dev/null
	done
done

# Wait for any remaining processes to finish before exiting
wait
