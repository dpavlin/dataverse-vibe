#!/bin/sh

# Function to convert bytes -> human readable
hr() {
    awk -v bytes="$1" '
    function human(x) {
        split("B KB MB GB TB PB", unit)
        i=1
        while (x >= 1024 && i < 6) { x/=1024; i++ }
        return sprintf("%.2f %s", x, unit[i])
    }
    BEGIN { print human(bytes) }'
}

# Print header
printf "%-60s %15s %12s %15s %12s\n" \
  "File" "ZIP bytes" "ZIP HR" "Uncompressed" "Unc HR"

# Collect rows in a temp file
outfile=$(mktemp)

find . -type f -name '*.zip' -print | while IFS= read -r zipfile; do
    # Compressed archive size (on disk)
    zipsize=$(stat -c %s "$zipfile")

    # Uncompressed size inside archive, taking only last line which include total size
    uncompressed=$(unzip -l "$zipfile" | awk '/^[ ]*[0-9][0-9]*  *[0-9][0-9]* file/ { print $1 }')

    printf "%-60s %15d %12s %15d %12s\n" \
        "$zipfile" \
        "$zipsize" "$(hr "$zipsize")" \
        "$uncompressed" "$(hr "$uncompressed")" | tee -a "$outfile"
done

# Now sum columns 2 and 5 (bytes and uncompressed)
total_zip=$(awk '{z+=$2} END{print z}' "$outfile")
total_uncompressed=$(awk '{u+=$5} END{print u}' "$outfile")

#rm -f "$outfile"
echo rm -f "$outfile"

echo "----------------------------------------------------------------------------------------------------"
echo "Total ZIP size:          $total_zip bytes ($(hr "$total_zip"))"
echo "Total uncompressed size: $total_uncompressed bytes ($(hr "$total_uncompressed"))"
