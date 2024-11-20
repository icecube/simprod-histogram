#!/bin/bash
set -euo pipefail

########################################################################################
# Script Name: Simprod Histogram Sampler
#
# Description: This script samples a subset of directories and files from a specified
#              source directory, preserving the directory structure, and copies them
#              to a destination directory in the user's home directory. It also provides
#              an option for a dry run to preview actions without making changes.
#
# Usage:       cp-src-histos-tree.sh <SOURCE_DIR> [--dryrun]
#
# Parameters:
#     SOURCE_DIR : The source directory containing the "*/histos" directories to sample from.
#     --dryrun   : Optional flag that, if provided, skips actual file and directory operations,
#                  outputting actions to be taken without modifying any files.
#
# Example:     cp-src-histos-tree.sh /path/to/source --dryrun
#
# Notes:
#     - Sampling percentages for directories and files are set to 10% by default.
#     - A README.md summary file is created in the destination directory, logging
#       the source information, sampling parameters, and resulting file statistics.
########################################################################################

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <SOURCE_DIR> [--dryrun]"
    exit 1
fi

########################################################################################

# Verify that the provided SOURCE_DIR exists and is a directory
if [ ! -d "$1" ]; then
    echo "Error: The specified source directory '$1' does not exist or is not a directory."
    exit 1
fi
SOURCE_DIR=$(realpath "$1")

# Determine if the --dryrun flag is provided
DRYRUN=false
if [ "$2" == "--dryrun" ]; then
    DRYRUN=true
fi

########################################################################################

# Assign the source directory and force destination to the user's home directory
DEST_DIR=$(realpath "$HOME/simprod-histograms") # Define the destination under the user's home directory

dir_sample_percentage=0.1  # 10% of directories
file_sample_percentage=0.1 # 10% of .pkl files in each selected directory

########################################################################################

echo "Starting the sampling and copying process for Simprod Histograms..."
echo "Source directory: $SOURCE_DIR"
echo "Destination directory: $DEST_DIR"
echo "Dry run: $DRYRUN"
echo "Sampling $(echo "$dir_sample_percentage * 100" | bc)% of directories and $(echo "$file_sample_percentage * 100" | bc)% of .pkl files within each directory."

# Prepare the destination directory
if [ "$DRYRUN" == true ]; then
    echo "[DRYRUN] mkdir -p $DEST_DIR"
else
    mkdir -p "$DEST_DIR"
fi

# Initialize counters for sampled directories and files
sampled_dir_count=0
sampled_file_count=0

# Find all directories matching "*/histos" and sample 10% of them
total_dirs=$(find "$SOURCE_DIR" -type d -path "*/histos" | wc -l)
sampled_dirs=$(echo "$total_dirs * $dir_sample_percentage" | bc | awk '{print int($1+0.5)}')

find "$SOURCE_DIR" -type d -path "*/histos" | shuf -n "$sampled_dirs" | while read -r subdir; do
    # Calculate the relative path from SOURCE_DIR and create the corresponding destination directory
    relative_subdir="${subdir#"$SOURCE_DIR"/}"
    dst_subdir="$DEST_DIR/$relative_subdir"
    if [ "$DRYRUN" == true ]; then
        echo "[DRYRUN] mkdir -p $dst_subdir"
    else
        mkdir -p "$dst_subdir"
    fi
    echo "Created directory: $dst_subdir"
    ((sampled_dir_count++))

    # Find and sample .pkl files, then copy each sampled file
    total_files=$(find "$subdir" -type f -name "*.pkl" | wc -l)
    sampled_files=$(echo "$total_files * $file_sample_percentage" | bc | awk '{print int($1+0.5)}')

    find "$subdir" -type f -name "*.pkl" | shuf -n "$sampled_files" | while read -r file; do
        # Define the destination file path to maintain directory structure
        dst_file="$dst_subdir/${file##*/}"
        echo "Copying $file to $dst_file"
        if [ "$DRYRUN" == true ]; then
            echo "[DRYRUN] cp $file $dst_file"
        else
            cp "$file" "$dst_file"
        fi
        ((sampled_file_count++))
    done
done

# Create a high-level README.md file in the main destination directory
readme_file="$DEST_DIR/README.md"
if [ "$DRYRUN" == false ]; then
    {
        echo "# Simprod Histograms"
        echo
        echo "This directory contains a sampled subset of histogram data files."
        echo
        echo "### Source Information"
        echo "- **Source Directory**: $SOURCE_DIR"
        echo "- **Sampling Parameters**: $(echo "$dir_sample_percentage * 100" | bc)% of directories and $(echo "$file_sample_percentage * 100" | bc)% of .pkl files within each selected directory."
        echo
        echo "### Destination Information"
        echo "- **Destination Directory**: $DEST_DIR"
        echo "- **Total Sampled Directories**: $sampled_dir_count"
        echo "- **Total Sampled .pkl Files**: $sampled_file_count"
    } >>"$readme_file"
else
    echo "[DRYRUN] Writing README.md to $readme_file"
fi

echo "Sampling and copying process complete. Summary written to $DEST_DIR/README.md."
