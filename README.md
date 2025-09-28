
# Dataverse Management Scripts

Mmanaging Dataverse instances updates

The scripts were created to address challenges encountered with disk usage and performance during data ingestion and system upgrades.


## Scripts

* `dv-upgrade.sh`: Automates the Dataverse upgrade process, including undeploying the old version, cleaning up generated files, and deploying the new version.
* `2025-03-29-upgrade-v6.1.sh`: script for upgrading to Dataverse 6.1, including loading new metadata blocks.
* `dataverse-vibe/export_dataset.sh`: Exports a Dataverse dataset to a local directory, creating a "hardlink farm" to preserve the original file structure and generating manifest files for file paths and MD5 checksums.
* `zip-size.sh`: Calculates the compressed and uncompressed sizes of ZIP archives, useful for analyzing disk space usage.

## Usage

These scripts are intended to be run from the command line. Please refer to the individual scripts for configuration options and usage instructions.
