
#!/usr/bin/env bash
# justjustify.sh - read lines from stdin, add prefix and suffix to each line
# Usage: justjustify.sh JUSTIFY_WIDTH PREFIX_TEXT SUFFIX_TEX
#
# Example:  cat text.input | ./justjustify.sh 19 "    echo \"" "\""
#           cat text.input | ./justjustify.sh 19 "# " " #"

VERSION="1.0.1"
DESCRIPTION="Read lines from stdin, justify the whole text with a specified width, and add prefix and suffix to each new line."

content=$(cat) # Read all input at once


justify_len=${1:-24}  # Default justify length is 24 characters, can be overridden by first argument
prefix=${2:-}
suffix=${3:-}

# term_width=$(( $(tput cols) - ${#prefix} - ${#suffix} ))
# term_height=$(tput lines)


# Read every line from stdin (preserve empty lines and final line without newline)
# while IFS= read -r line || [ -n "$line" ]; do
# 	printf '%s%s%s\n' "$prefix" "$line" "$suffix"
# done

groff_content='.ll '"$justify_len"$'\n'
groff_content+=$content
groff_content+=$'\n''.pl \n[nl]u'

echo "Content to justify:"
echo "$groff_content"
echo
echo "Justified content:"

result_content=""
while IFS= read -r line; do 
    if [[ ! -z "$line" ]]; then
        result_content+="$prefix$line$suffix\n"
    fi
done < <(groff -k -mpl -Tutf8 <<< "$groff_content")

echo -e "$result_content"
