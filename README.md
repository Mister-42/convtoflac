## Introduction

[FLAC](http://flac.sourceforge.net/) is a free, open source lossless compression audio codec. The Convert to FLAC script converts audio files compressed with alternative lossless codecs (Monkey's Audio, Shorten, etc.) to the FLAC format. FLAC is my preferred audio format for archiving music, so I wanted an easy way to convert other formats to FLAC. In addition to simply transcoding the file to the FLAC format, Convert to FLAC also preserves any existing tags from the original file.

Convert to FLAC is a BASH shell script, and was originally written for use under Linux. It should, however, run under any OS that supports BASH (please let me know if you find any bugs in cross-platform support).

Convert to FLAC currently supports the following input formats:

*   [Apple Lossless](http://en.wikipedia.org/wiki/Apple_Lossless) (ALAC) - requires [alac](http://craz.net/programs/itunes/alac.html) and [mp4info](http://mpeg4ip.sourceforge.net/) (for metadata) binaries
*   [FLAC](http://flac.sourceforge.net/) (eg., for transcoding to a different compression ratio)
*   [Meridian Lossless Packing](https://en.wikipedia.org/wiki/Meridian_Lossless_Packing) (MLP) - commonly found on DVD-Audio and Blu-ray discs; requires `ffmpeg`
*   [Monkey's Audio](http://www.monkeysaudio.com/) (APE) - requires [mac](http://www.supermmx.org/linux/mac/) and [apeinfo](http://legroom.net/software/apeinfo) (for metadata) binaries
*   [Shorten](http://www.etree.org/shnutils/shorten/) - requires `shorten` binary
*   [True Audio](http://www.true-audio.com/) (TTA) - requires `ttaenc` binary
*   [WAVE](http://en.wikipedia.org/wiki/WAV)
*   [WavPack](http://www.wavpack.com/) - requires `wvunpack` binary
*   [Windows Media Audio Lossless](https://en.wikipedia.org/wiki/Windows_Media_Audio#Windows_Media_Audio_Lossless) (WMA) - requires `ffmpeg`

**Note:** As of version 2.1, Convert to FLAC supports [ffmpeg](http://www.ffmpeg.org/) as an optional decoder, which can be used to convert files if you do not have the required binaries as listed above (eg., for converting APE files, since `mac` can be difficult to find and install). Please be aware that using ffmpeg as an alternative also has its drawbacks:

*   ffmpeg cannot read metadata, so any existing tags will not be copied to the new FLAC file
*   not all fomats are supported; ffmpeg can only be used for ALAC, APE, MLP, Shorten, WavPack, and WMA Lossless files
*   ffmpeg cannot pipe output directly to the `flac`, so the conversion process will take longer as it must first write out a temporary WAV file
