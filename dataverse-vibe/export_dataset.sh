#!/bin/sh

# ====================================================================================
# Dataverse Dataset Exporter - Hardlinks & Manifests (v11 - POSIX /bin/sh Compliant)
#
# Creates a "hardlink farm" of a Dataverse dataset, preserving the original file
# structure. It also generates two manifest files within the export directory:
#
#   1. oid.files: A plain list of all file paths relative to the export root.
#   2. oid.md5:   An md5sum-compatible checksum file using the original MD5s
#                 from the Dataverse database.
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

# Use unique temporary files for the queries
FILES_TEMP_FILE="/tmp/dataverse_files.$$.tmp"
MD5_TEMP_FILE="/tmp/dataverse_md5s.$$.tmp"

# POSIX-compliant trap to automatically clean up all temporary files on exit
trap 'rm -f "$FILES_TEMP_FILE" "$MD5_TEMP_FILE"' 0 INT TERM HUP

# Parse the DOI
DOI_PROTOCOL=$(echo "$DATASET_DOI" | cut -d: -f1)
DOI_REST=$(echo "$DATASET_DOI" | cut -d: -f2-)
DOI_AUTHORITY=$(echo "$DOI_REST" | cut -d/ -f1)
DOI_IDENTIFIER=$(echo "$DOI_REST" | cut -d/ -f2-)

# Define the final export directory and manifest paths
EXPORT_DIR="$EXPORT_BASE_DIR/$DOI_IDENTIFIER"
FILES_LIST_PATH="$EXPORT_DIR/$DOI_IDENTIFIER.files"
MD5_LIST_PATH="$EXPORT_DIR/$DOI_IDENTIFIER.md5"

echo "--- Dataverse Dataset Exporter (Hardlink & Manifest Mode) ---"
echo "Dataset DOI:         $DATASET_DOI"
echo "Export Directory:      $EXPORT_DIR"
echo "---------------------------------------------------------------"

mkdir -p "$EXPORT_DIR"
# Initialize/clear manifest files for this run
> "$FILES_LIST_PATH"
> "$MD5_LIST_PATH"
echo "Created export directory and initialized manifest files."

# --- STEP 1: Get file locations and create hardlinks ---

FILE_INFO_SQL="
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
        SELECT dv.id FROM datasetversion dv JOIN dvobject dvo ON dv.dataset_id = dvo.id
        WHERE dvo.protocol = '${DOI_PROTOCOL}' AND dvo.authority = '${DOI_AUTHORITY}'
        AND dvo.identifier = '${DOI_IDENTIFIER}' AND dv.versionstate = 'RELEASED'
        ORDER BY dv.versionnumber DESC, dv.minorversionnumber DESC LIMIT 1
    );
"

echo "Querying for file locations and writing to temp file..."
sudo -u postgres psql -d "$DB_NAME" -t -A -F'|' -c "$FILE_INFO_SQL" > "$FILES_TEMP_FILE"

echo "Processing file list, creating hardlinks and .files manifest..."
file_count=0
total_size=0

while IFS='|' read -r storage_id directory_label original_filename; do
    if [ -z "$storage_id" ]; then continue; fi

    relative_file_id=$(echo "$storage_id" | sed 's#^file://##')
    source_file_path="$DATAVERSE_FILES_DIR/$DOI_AUTHORITY/$DOI_IDENTIFIER/$relative_file_id"
    destination_dir="$EXPORT_DIR"
    
    # Construct relative path for manifests first
    relative_path="$original_filename"
    if [ -n "$directory_label" ]; then
        destination_dir="$EXPORT_DIR/$directory_label"
        relative_path="$directory_label/$original_filename"
    fi
    
    destination_path="$destination_dir/$original_filename"
    mkdir -p "$destination_dir"

    if [ -f "$source_file_path" ]; then
        file_size_bytes=$(stat -c %s "$source_file_path")
        hr_size=$(human_readable_size "$file_size_bytes")

        printf "Hardlinking [%9s] -> %s\n" "$hr_size" "$destination_path"
        sudo ln -f "$source_file_path" "$destination_path"
        
        # Append to the .files manifest
        echo "$relative_path" >> "$FILES_LIST_PATH"
        
        file_count=$(($file_count + 1))
        total_size=$(($total_size + $file_size_bytes))
    else
        printf "  WARNING: Source file not found, skipping: %s\n" "$source_file_path"
    fi
done < "$FILES_TEMP_FILE"

echo "Hardlinking complete. Processed $file_count files."

# --- STEP 2: Get MD5 checksums and create .md5 manifest ---

MD5_INFO_SQL="
SELECT
    df.checksumvalue,
    COALESCE(fmd.directorylabel, ''),
    fmd.label
FROM
    filemetadata fmd
JOIN
    datafile df ON fmd.datafile_id = df.id
WHERE
    df.checksumtype = 'MD5' AND
    fmd.datasetversion_id = (
        SELECT dv.id FROM datasetversion dv JOIN dvobject dvo ON dv.dataset_id = dvo.id
        WHERE dvo.protocol = '${DOI_PROTOCOL}' AND dvo.authority = '${DOI_AUTHORITY}'
        AND dvo.identifier = '${DOI_IDENTIFIER}' AND dv.versionstate = 'RELEASED'
        ORDER BY dv.versionnumber DESC, dv.minorversionnumber DESC LIMIT 1
    );
"
echo "Querying database for MD5 checksums..."
sudo -u postgres psql -d "$DB_NAME" -t -A -F'|' -c "$MD5_INFO_SQL" > "$MD5_TEMP_FILE"

echo "Creating .md5 manifest file..."
md5_count=0
while IFS='|' read -r checksum directory_label original_filename; do
    if [ -z "$checksum" ]; then continue; fi

    relative_path="$original_filename"
    if [ -n "$directory_label" ]; then
        relative_path="$directory_label/$original_filename"
    fi
    
    # Format for md5sum: CHECKSUM  ./FILENAME
    echo "$checksum  ./$relative_path" >> "$MD5_LIST_PATH"
    md5_count=$(($md5_count + 1))
done < "$MD5_TEMP_FILE"

# --- FINAL SUMMARY ---

hr_total_size=$(human_readable_size "$total_size")

echo "---------------------------------------------------------------"
echo "Export complete!"
echo "  - Total files linked:   $file_count"
echo "  - Total checksums written: $md5_count"
echo "  - Total dataset size:     $hr_total_size"
echo "  - Hardlink farm created at: $EXPORT_DIR"
echo "  - File list created at:     $FILES_LIST_PATH"
echo "  - MD5 manifest created at:  $MD5_LIST_PATH"
echo "---------------------------------------------------------------"
echo "To verify the checksums, cd to the export directory and run:"
echo "cd '$EXPORT_DIR' && md5sum -c '$DOI_IDENTIFIER.md5'"
echo
