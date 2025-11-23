#!/usr/bin/env bash

# copies `public` headers to `Sources/taglib/include/taglib` which is a requirement for this module to compile
# bless this script with `chmod u+x` to make it executable if it's not already

source_directories=("taglib/taglib" "taglib/bindings")
destination_directory="include/taglib"

mkdir -p "$destination_directory"

for source_directory in "${source_directories[@]}"; do
    find "$source_directory" -type f \( -name "*.h" -o -name "*.tcc" \) -exec cp -f "{}" "$destination_directory" \;
done
