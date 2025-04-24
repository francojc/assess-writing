#!/usr/bin/env bash

# This script converts a PDF file to a PNG file using imagemagick's convert.
# The output PNG file is saved in the pngs/ directory with the same filename as the input PDF file.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <input_pdf_file>

Options:
  -h, --help    Show this help message and exit

Converts PDF files to PNG format using imagemagick. 

Requirements:
  - imagemagick must be installed
  - Input file must be a valid PDF

Example:
  $0 my_document.pdf

EOF
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Check if imagemagick's convert is installed
if ! command -v magick &> /dev/null; then
  echo "Error: imagemagick is not installed. Please install it to use this script."
  exit 1
fi

# Check if an input file is provided
if [ -z "$1" ]; then
  usage
  exit 1
fi

input_pdf="$1"

# Check if the input file exists and is a PDF file
if [[ ! -f "$input_pdf" || ! "$input_pdf" =~ \.pdf$ ]]; then
  echo "Error: Input file '$input_pdf' is not a valid PDF file."
  exit 1
fi

# Create the pngs directory if it doesn't exist
mkdir -p pngs

# Extract the filename without extension
filename=$(basename "$input_pdf" .pdf)

# Define the output PNG filename and directory
output_png="pngs/${filename}.png"

# Convert the PDF to PNG using imagemagick's convert and append all pages vertically
magick -density 300 "$input_pdf" -append "$output_png"

echo "Successfully converted '$input_pdf' to '$output_png'"
