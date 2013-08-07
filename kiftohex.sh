#!/bin/bash

# Read a Kerning Input File and build a 'kern' table in hex formatted for OS X Font Tools
# Copyright 2013 Grzegorz Rolek
#
# Kerning Input File format, although mentioned few times in the OS X Font Tools docs,
# has never been publicly released by Apple. The file this script reads tries to
# approximate the syntax based on the Morph Input File and its support in Font Tools.
#
# The script needs an accompanying 'post' table in the Font Tools XML format.
# Usage: kiftohex.sh -p <post.xml> <kern.kif>


# Parse and reset the arguments.
set $(getopt p: $*)

# Make sure there are all necessary arguments given.
test $# != 3 && { echo >&2 "usage: $(basename $0) -p <post.xml> <kern.kif>"; exit 2; }

# Parse the 'post' table file for an array of glyphs names.
glyphs=($(sed -n 's/<PostScriptName ..* NameString=\"\(..*\)\".*>/\1/p' <$1))

# Remove comments from the KIF file.
KIF="$(sed -e '/^\/\/.*/d' -e 's/[ 	]*\/\/.*//' $3)"

# Sets index of a token within the list following the token.
indexof () {
	index=0
	token=$1; shift
	for item; do test $token = $item && return; let index++; done
	index=-1
}

off=0 # Offset into the table
nsubtables=$(grep -c '^Type ' <<<"$KIF") # No. of subtables
subindex=1 # Index of a particular subtable

printf "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n"
printf "<genericSFNTTable tag=\"kern\">\n"
printf "\t<dataline offset=\"%08X\" hex=\"%04X%04X\"/> <!-- Table version -->\n" $off 1 0 && let off+=4
printf "\t<dataline offset=\"%08X\" hex=\"%08X\"/> <!-- No. of subtables -->\n" $off $nsubtables && let off+=4

EOF=0

# Read the KIF subtable by subtable until the end of file.
while test $EOF -ne 1
do

	format=0 # Subtable's coverage flags and format
	classes=() # GID-indexed array of classes
	clnames=(EOT OOB DEL EOL) # Class names
	unset startgid # First glyph assigned to a class
	unset endgid # Last glyph assigned to a class
	states=() # State records
	stnames=() # State names
	gotos=() # Next states
	gonames=() # Names of the next states
	actions=() # Kern value lists to apply
	actnames=() # Names of kern value lists to apply
	values=() # Kerning values
	valnames=() # Names of the kern value lists
	valindices=() # Indexes of values beginning the lists

	# Skip blank lines.
	until test "$REPLY"; do read; done

	line=($REPLY)
	test $line != "Type" && { echo >&2 "fatal: kerning type expected"; exit 1; }
	case ${line[@]:1} in
	Contextual) format=1;;
	*) echo >&2 "fatal: unknown kerning type: ${line[@]:1}"; exit 1;;
	esac

	unset REPLY; until test "$REPLY"; do read; done

	line=($REPLY)
	test $line != "Orientation" && { echo >&2 "fatal: kerning orientation expected"; exit 1; }
	case ${line[@]:1} in
	V) let format+=16#8000;;
	H) ;;
	*) echo >&2 "fatal: unknown orientation: ${line[@]:1}"; exit 1;;
	esac

	unset REPLY; until test "$REPLY"; do read; done

	line=($REPLY)

	if test $line = "Cross-stream"
	then
		case ${line[@]:1} in
		yes) let format+=16#4000;;
		no) ;;
		*) echo >&2 "fatal: not a yes/no value for cross-stream: ${line[@]:1}"; exit 1;;
		esac

		unset REPLY; until test "$REPLY"; do read; done
		line=($REPLY)
	fi

	if test $line = "Variation"
	then
		case ${line[@]:1} in
		yes) let format+=16#2000;;
		no) ;;
		*) echo >&2 "fatal: not a yes/no value for variation: ${line[@]:1}"; exit 1;;
		esac

		unset REPLY; until test "$REPLY"; do read; done
	fi

	let nclasses=4 # four built-in classes
	while true
	do
		# Skip blank lines, but break on a state table header (indented line).
		test "$REPLY" || { read; continue; }
		grep -q '^[a-zA-Z]' <<<"$REPLY" || break

		line=($REPLY)
		clnames[${#clnames[@]}]=$line

		for glyph in ${line[@]:1}
		do
			indexof $glyph ${glyphs[@]}
			test $index -eq -1 && { echo >&2 "fatal: glyph not found: $glyph"; exit 1; }
			classes[$index]=$nclasses
			test $index -lt ${startgid=$index} && startgid=$index
			test $index -gt ${endgid=$index} && endgid=$index
		done

		let nclasses++

		read
	done

	# Set an Out-of-Bounds class on glyphs inbetween the specified ones.
	for i in $(seq $startgid $endgid)
	do test "${classes[$i]}" || classes[$i]=1
	done

	let ngids=$endgid-$startgid+1
	let clpadding=$ngids%2
	let offclasses=10 # constant
	let offstates=$offclasses+4+$ngids+$clpadding # 4 for the glyph range

	# Check if the class list and state table header match.
	header=($REPLY)
	test "${clnames[*]}" != "${header[*]}" && { echo >&2 "fatal: classes and state header don't match"; exit 1; }

	# Skip any blanks under the state table header, but not in the table itself.
	unset REPLY; until test "$REPLY"; do read; done

	while true
	do
		# Break on a blank line or an entry table header.
		test "$REPLY" || break
		grep -q '^[a-zA-Z]' <<<"$REPLY" || break

		line=($REPLY)
		stnames=(${stnames[@]} $line)

		# Make the entry numbers zero-based.
		state=()
		for entry in ${line[@]:1}
		do
			let entry--
			state=(${state[@]} $entry)
		done

		test "${#state[@]}" -ne "$nclasses" && { echo >&2 "fatal: wrong entry count in state: $line"; exit 1; }
		states[${#states[@]}]="${state[@]}"
		read
	done

	nstates=${#states[@]}
	let stpadding=$nstates*$nclasses%2
	let offentries=$offstates+$nstates*$nclasses+$stpadding

	# Skip any more blanks if necessary.
	until test "$REPLY"; do read; done

	# Check if the entry table header is as expected.
	header=($REPLY)
	test "${header[*]}" != "GoTo Push? Advance? KernValues" && { echo >&2 "fatal: malformed entry table header"; exit 1; }

	# Skip any blanks under the entry table header.
	unset REPLY; until test "$REPLY"; do read; done

	while true
	do
		# Break on a blank, but also on an indented line (the Font Tools way).
		test "$REPLY" || break
		grep -q '^[a-zA-Z0-9_]' <<<"$REPLY" || break

		line=($REPLY)
		let entry=${#gotos[@]}+1
		test $line -eq $entry || { echo >&2 "fatal: wrong number for entry listed as $entry"; exit 1; }

		indexof ${line[@]:1:1} ${stnames[@]}
		test $index -eq -1 && { echo >&2 "fatal: state not found: ${line[@]:1:1}"; exit 1; }
		let goto=$offstates+$index*$nclasses
		gotos=(${gotos[@]} $goto)
		gonames=(${gonames[@]} ${line[@]:1:1})

		action=0
		test ${line[@]:2:1} = "yes" && let action+=16#8000 # Push?
		test ${line[@]:3:1} = "yes" || let action+=16#4000 # Don't Advnance?
		actions=(${actions[@]} $action)
		actnames=(${actnames[@]} ${line[@]:4:1})

		read
	done

	let offvalues=$offentries+${#gotos[@]}*4

	while true
	do
		# Skip blank lines, but break on a next subtable, or with file's end.
		test $EOF -eq 1 && break
		test "$REPLY" || { read || EOF=1; continue; }
		grep -q 'Type' <<<"$REPLY" && break

		line=($REPLY)
		valnames=(${valnames[@]} $line)
		valindices=(${valindices[@]} ${#values[@]})

		for value in ${line[@]:1}
		do
			# Make a 2's complement in case of a negative value.
			test $value -lt 0 && let value=16#10000+$value

			# Unset the least significant bit for each value.
			let value-=$value%2

			values=(${values[@]} $value)
		done

		# Set the list-end flag for the last value.
		values[((${#values[@]}-1))]=$((value+=1))

		read || EOF=1
	done

	let length=$offvalues+${#values[@]}*2+8

	# Now with the values parsed, calculate the offsets.
	for i in ${!actions[@]}
	do
		valname=${actnames[$i]}
		action=${actions[$i]}

		if test $valname != "none"
		then
			indexof $valname ${valnames[@]}
			test $index -eq -1 && { echo >&2 "fatal: kern value list not found: $valname"; exit 1; }
			let action+=$offvalues+${valindices[$index]}*2
		fi

		actions[$i]=$action
	done

	printf "\n"
	printf "\t<!-- Subtable No. %d -->\n" $((subindex++))
	printf "\n"
	printf "\t<dataline offset=\"%08X\" hex=\"%08X\"/> <!-- Subtable length -->\n" $off $length && let off+=4
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- Subtable coverage/format -->\n" $off $format && let off+=2
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- Subtable tuple index -->\n" $off 0 && let off+=2
	printf "\n"
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- No. of classes -->\n" $off $nclasses && let off+=2
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- Offset to classes -->\n" $off $offclasses && let off+=2
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- Offset to states -->\n" $off $offstates && let off+=2
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- Offset to entries -->\n" $off $offentries && let off+=2
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- Offset to values -->\n" $off $offvalues && let off+=2
	printf "\n"
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- First glyph -->\n" $off $startgid && let off+=2
	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/> <!-- No. of glyphs -->\n" $off $ngids && let off+=2

	printf "\n"
	for i in $(seq $startgid $endgid); do
	printf "\t<dataline offset=\"%08X\" hex=\"%02X\"/> <!-- %s\t%s -->\n" $off ${classes[$i]} ${clnames[${classes[$i]}]} ${glyphs[$i]} && let off+=1
	done
	if test $clpadding -eq 1; then
	printf "\t<dataline offset=\"%08X\" hex=\"00\"/> <!-- Padding -->\n" $off && let off+=1
	fi

	printf "\n"
	printf "\t                            <!-- "
		printf "%-2.2s " ${clnames[@]}
		printf " -->\n"
	for i in ${!states[@]}; do
	printf "\t<dataline offset=\"%08X\" hex=\"" $off
		printf "%02X " ${states[$i]} && let off+=$nclasses
		printf "\"/> <!-- %s -->\n" ${stnames[$i]}
	done
	if test $stpadding -eq 1; then
	printf "\t<dataline offset=\"%08X\" hex=\"00\"/> <!-- Padding -->\n" $off && let off+=1
	fi

	printf "\n"
	printf "\t                                              <!--    GoTo -->\n"
	for i in ${!gotos[@]}; do
	printf "\t<dataline offset=\"%08X\" hex=\"%04X %04X\"/> <!-- %02X %s -->\n" $off ${gotos[$i]} ${actions[$i]} $i ${gonames[$i]} && let off+=4 
	done

	printf "\n"
	i=0; j=0
	for value in ${values[@]}
	do
		# Print the list's name on its first value only.
		unset valname
		test $((i++)) -eq ${valindices[$j]} && valname=" <!-- ${valnames[((j++))]} -->"

	printf "\t<dataline offset=\"%08X\" hex=\"%04X\"/>%s\n" $off $value "$valname" && let off+=2
	done

done <<<"$KIF"

printf "\n</genericSFNTTable>\n"
exit
