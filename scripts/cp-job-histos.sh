#!/bin/bash
set -euo pipefail

########################################################################################
# Script Name: Simprod Job Histogram Copier
#
# Description: This script copies a percentage of directories and `.pkl` files from
#              "*/histos" directories in the specified dataset directory. These
#              "histos" directories contain **job-level histograms**, not dataset-level
#              histograms. The script preserves the directory structure while copying
#              the data to a destination directory in the user's home folder. An option
#              for a dry run is provided to preview the actions without making any changes.
#
# Usage:       cp-job-histos.sh <DATASET_DIR> [--dryrun]
#
# Parameters:
#     DATASET_DIR : The dataset directory containing the "*/histos" directories to copy from.
#     --dryrun    : Optional flag that, if provided, skips actual file and directory operations,
#                   outputting actions to be taken without modifying any files.
#
# Notes:
#     - Copy-percentages for directories and files are set to 10% by default.
#     - A README.md summary file is created in the destination directory, logging
#       the dataset directory, parameters, and resulting file statistics.
#     - This script only handles job histograms (e.g., `.pkl` files within the
#       "*/histos" directories) and excludes dataset-level histograms.
########################################################################################

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <DATASET_DIR> [--dryrun]"
    exit 1
fi

########################################################################################

# Verify that the provided DATASET_DIR exists and is a directory
if [ ! -d "$1" ]; then
    echo "Error: The specified dataset directory '$1' does not exist or is not a directory."
    exit 1
fi
DATASET_DIR=$(realpath "$1")

# Determine if the --dryrun flag is provided
DRYRUN=false
for arg in "$@"; do
    if [[ $arg == "--dryrun" ]]; then
        DRYRUN=true
        break
    fi
done

########################################################################################

# Assign the dataset directory and force destination to the user's home directory
DEST_DIR=$(realpath "$HOME/simprod-histograms") # Define the destination under the user's home directory

dir_copy_percentage=0.1  # 10% of directories
file_copy_percentage=0.1 # 10% of .pkl files in each selected directory

########################################################################################

echo "Starting the copying process for Simprod Job Histograms..."
echo "Dataset directory: $DATASET_DIR"
echo "Destination directory: $DEST_DIR"
echo "Dry run: $DRYRUN"
echo "Copying $(echo "$dir_copy_percentage * 100" | bc)% of directories and $(echo "$file_copy_percentage * 100" | bc)% of .pkl files within each directory."

# Prepare the destination directory
if [ "$DRYRUN" == true ]; then
    echo "[DRYRUN] mkdir -p $DEST_DIR"
else
    mkdir -p "$DEST_DIR"
fi

# Initialize counters for copied directories and files
copied_dir_count=0
copied_file_count=0

# Find all directories matching "*/histos" and copy a percentage of them
total_dirs=$(find "$DATASET_DIR" -type d -path "*/histos" | wc -l)
dirs_to_copy=$(echo "$total_dirs * $dir_copy_percentage" | bc | awk '{print int($1+0.5)}')

find "$DATASET_DIR" -type d -path "*/histos" | shuf -n "$dirs_to_copy" | while read -r subdir; do
    # Calculate the relative path from DATASET_DIR and create the corresponding destination directory
    relative_subdir="${subdir#"$DATASET_DIR"/}"
    dst_subdir="$DEST_DIR/$relative_subdir"
    if [ "$DRYRUN" == true ]; then
        echo "[DRYRUN] mkdir -p $dst_subdir"
    else
        mkdir -p "$dst_subdir"
    fi
    echo "Created directory: $dst_subdir"
    ((copied_dir_count++))

    # Find and copy a percentage of .pkl files
    total_files=$(find "$subdir" -type f -name "*.pkl" | wc -l)
    files_to_copy=$(echo "$total_files * $file_copy_percentage" | bc | awk '{print int($1+0.5)}')

    find "$subdir" -type f -name "*.pkl" | shuf -n "$files_to_copy" | while read -r file; do
        # Define the destination file path to maintain directory structure
        dst_file="$dst_subdir/${file##*/}"
        echo "Copying $file to $dst_file"
        if [ "$DRYRUN" == true ]; then
            echo "[DRYRUN] cp $file $dst_file"
        else
            cp "$file" "$dst_file"
        fi
        ((copied_file_count++))
    done
done

# Create a high-level README.md file in the main destination directory
readme_file="$DEST_DIR/README.md"
if [ "$DRYRUN" == false ]; then
    {
        echo "# Simprod Job Histograms"
        echo
        echo "This directory contains a subset of job histogram data files."
        echo
        echo "### Source Information"
        echo "- **Dataset Directory**: $DATASET_DIR"
        echo "- **Copy Parameters**: $(echo "$dir_copy_percentage * 100" | bc)% of directories and $(echo "$file_copy_percentage * 100" | bc)% of .pkl files within each selected directory."
        echo
        echo "### Destination Information"
        echo "- **Destination Directory**: $DEST_DIR"
        echo "- **Total Copied Directories**: $copied_dir_count"
        echo "- **Total Copied .pkl Files**: $copied_file_count"
    } >>"$readme_file"
else
    echo "[DRYRUN] Writing README.md to $readme_file"
fi

echo "Copying process complete. Summary written to $DEST_DIR/README.md."
