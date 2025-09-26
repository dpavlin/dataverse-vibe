#!/bin/sh

# ====================================================================================
# Dataverse Dataset Exporter - Hardlink & Verbose (v10 - POSIX /bin/sh Compliant)
#
# Creates a "hardlink farm" of a Dataverse dataset, preserving the original file
# structure. Provides verbose output for each file, including its size.
#
# CRITICAL: Hardlinks CANNOT cross filesystems. The source and destination
#           directories MUST be on the same disk partition.
# ====================================================================================

# --- CONFIGURE THESE VARIABLES ---

DATASET_DOI="doi:10.23669/1ZTELP"
EXPORT_BASE_DIR="exports"
DATAVERSE_FILES_DIR="/usr/local/dvn/data"
DB_NAME="dvndb"

# --- SCRIPT LOGIC ---

set -e # Exit immediately if a command exits with a non-zero status.

# POSIX-compliant function to convert bytes to human-readable format
human_readable_size() {
    bytes=$1
    echo "$bytes" | awk '
        function human(x) {
            s=" B  KB MB GB TB PB EB";
            while (x >= 1024 && length(s) > 1) {
                x /= 1024;
                s = substr(s, 4);
            }
            s = substr(s, 1, 4);
            return sprintf("%.1f%s", x, s);
        }
        { print human($1) }
    '
}

# Use a unique temporary file for the file list
TEMP_FILE="/tmp/dataverse_export_files.$$.tmp"

# POSIX-compliant trap to automatically clean up the temporary file on exit
trap 'rm -f "$TEMP_FILE"' 0 INT TERM HUP

# Parse the DOI
DOI_PROTOCOL=$(echo "$DATASET_DOI" | cut -d: -f1)
DOI_REST=$(echo "$DATASET_DOI" | cut -d: -f2-)
DOI_AUTHORITY=$(echo "$DOI_REST" | cut -d/ -f1)
DOI_IDENTIFIER=$(echo "$DOI_REST" | cut -d/ -f2-)

# Define the final export directory
EXPORT_DIR="$EXPORT_BASE_DIR/$DOI_IDENTIFIER"

echo "--- Dataverse Dataset Exporter (Hardlink Mode) ---"
echo "Dataset DOI:         $DATASET_DOI"
echo "Export Directory:      $EXPORT_DIR"
echo "Dataverse Files Dir:   $DATAVERSE_FILES_DIR"
echo "----------------------------------------------------"

mkdir -p "$EXPORT_DIR"
echo "Created export directory: $EXPORT_DIR"

# SQL query
SQL_QUERY="
SELECT
    dv_file.storageidentifier,
    COALESCE(fmd.directorylabel, ''),
    fmd.label
FROM
    filemetadata fmd
JOIN
    dvobject dv_file ON fmd.datafile_id = dv_file.id
WHERE
    fmd.datasetversion_id = (
        SELECT dv.id
        FROM datasetversion dv
        JOIN dvobject dvo ON dv.dataset_id = dvo.id
        WHERE
            dvo.protocol = '${DOI_PROTOCOL}'
            AND dvo.authority = '${DOI_AUTHORITY}'
            AND dvo.identifier = '${DOI_IDENTIFIER}'
            AND dv.versionstate = 'RELEASED'
        ORDER BY
            dv.versionnumber DESC, dv.minorversionnumber DESC
        LIMIT 1
    );
"

echo "Querying database and writing to temporary file..."
sudo -u postgres psql -d "$DB_NAME" -t -A -F'|' -c "$SQL_QUERY" > "$TEMP_FILE"

echo "Processing file list and creating hardlinks..."
file_count=0
total_size=0

# Use input redirection to feed the loop, avoiding a subshell.
while IFS='|' read -r storage_id directory_label original_filename; do
    if [ -z "$storage_id" ]; then
        continue
    fi

    relative_file_id=$(echo "$storage_id" | sed 's#^file://##')
    source_file_path="$DATAVERSE_FILES_DIR/$DOI_AUTHORITY/$DOI_IDENTIFIER/$relative_file_id"
    destination_dir="$EXPORT_DIR"
    
    if [ -n "$directory_label" ]; then
        destination_dir="$EXPORT_DIR/$directory_label"
    fi
    
    destination_path="$destination_dir/$original_filename"
    mkdir -p "$destination_dir"

    if [ -f "$source_file_path" ]; then
        # Get file size for verbose output
        file_size_bytes=$(stat -c %s "$source_file_path")
        hr_size=$(human_readable_size "$file_size_bytes")

        # Use printf for nicely aligned output
        printf "Hardlinking [%9s] -> %s\n" "$hr_size" "$destination_path"

        # Create the hardlink, forcing overwrite if it exists
        sudo ln -f "$source_file_path" "$destination_path"
        
        # POSIX-compliant arithmetic
        file_count=$(($file_count + 1))
        total_size=$(($total_size + $file_size_bytes))
    else
        printf "  WARNING: Source file not found, skipping: %s\n" "$source_file_path"
    fi
done < "$TEMP_FILE"

hr_total_size=$(human_readable_size "$total_size")

echo "----------------------------------------------------"
echo "Export complete!"
echo "Processed $file_count files."
echo "Total dataset size: $hr_total_size"
echo "Hardlink farm created at: $EXPORT_DIR"
