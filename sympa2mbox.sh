#!/bin/bash
 
# This scripts takes a sympa email archive and converts it into a
# single mbox file
 
path="$1"
dest="$2"
 
function die()
{
	echo "$1"
	exit
}
 
# ensure arguments are passed
[ -z "$path" ] && die "Pass archive directory as first argument."
[ -z "$dest" ] && die "Pass destination mbox file name as second argument."
 
# sanity checking
[ ! -d "$path" ] && die "Can't find '$path'"
touch "$dest" || die "Can't write to '$dest'"
 
# we rely on directories being name in alpha order oldest -> newest 
for dir in $(ls "$path"); do
	if [ -d "$path/$dir" ]; then
		echo -n "Working on $path/$dir..."
		files=$(ls "$path/$dir" | sort -n)
		for file in $files; do
			formail -ds < $path/$dir/$file >> $dest
		done
		echo "done"
	fi
done
