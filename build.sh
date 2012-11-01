#!/bin/bash

# Build script for Narzędzia Sukcesu the logotype font
# Copyright 2012 Grzegorz Rolek


# Make sure the OS X Font Tools are available.
for TOOL in ftxdumperfuser ftxenhancer
do type $TOOL &>/dev/null || { echo >&2 "Fatal: Make sure you have OS X Font Tools installed."; exit 1; }
done

# Clean up existing builds, if any.
rm -rf build && mkdir build

# Prepare the target for compilation.
TARGET=build/NarzedziaSukcesu.ttf
cp Null.ttf $TARGET

# Now compile. Note the table order, it's imporant.
# First fuse the basic required stuff.
for TABLE in head name maxp glyf cmap hmtx hhea post
do ftxdumperfuser --datafile $TABLE.xml --table $TABLE $TARGET
done

# Include the morph table.
ftxenhancer --mif morphing.mif $TARGET

# State machine kerning and ligature caret entries as generic hex data.
for TABLE in kern lcar
do ftxdumperfuser --datafile $TABLE.xml --generic --table $TABLE $TARGET
done

# Treat the final font with an autohinter, if available.
if type ttfautohint &>/dev/null
then

	# Make a temporary move just to have a path to make a hinting from.
	TMP_TARGET=build/$(basename -s .ttf $TARGET)_unhinted.ttf
	mv $TARGET $TMP_TARGET

	# Do the autohinting.
	ttfautohint --latin-fallback --symbol --no-info $TMP_TARGET $TARGET

	# Clean up.
	rm $TMP_TARGET

else echo >&2 "Note: The 'ttfautohint' wasn't found; the font hasn't been hinted."
fi

# That's it.
exit
