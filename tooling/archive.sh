#!/bin/bash

set -e

cd "${SDK_ROOT_DIR}"

find ./reports -type f | xargs ls -lh | awk '{print $5 "," $6 " " $7 " " $8 "," $9}' > artifacts.csv

# This little nugget of bash magic should replace all spaces in filenames with
# underscores
# see http://unix.stackexchange.com/questions/223182/how-to-replace-spaces-in-all-file-names-with-underscore-in-linux-using-shell-scr
find ./reports -name "* *" -print0 | sort -rz | \
  while read -d $'\0' f; do mv -v "$f" "$(dirname "$f")/$(basename "${f// /_}")"; done

gzip -r ./reports
mv artifacts.csv ./reports/artifacts.csv
