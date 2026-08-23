#!/usr/bin/env bash
# convert-fbc-to-basic-template.sh
# Usage: ./convert-fbc-to-basic-template.sh input.yaml output.yaml

set -euo pipefail

INPUT_FILE="${1:-catalog.yaml}"
OUTPUT_FILE="${2:-basic.yaml}"
YQ=${3:-./bin/yq}

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File '$INPUT_FILE' does not exist."
    exit 1
fi

cat > "$OUTPUT_FILE" <<EOF
---
schema: olm.template.basic
entries:
EOF

# Append olm.package, olm.channel, and olm.bundle objects properly as list items
$YQ eval-all -P '[
    (select(.schema == "olm.package") | {"schema": "olm.package", "name": .name, "defaultChannel": .defaultChannel, "icon": .icon}),
    (select(.schema == "olm.bundle") | {"schema": "olm.bundle", "image": .image}),
    (select(.schema == "olm.channel") | {"schema": "olm.channel", "name": .name, "package": .package, "entries": .entries})
  ]
' "$INPUT_FILE" | \
  sed 's/^/  /' >> "$OUTPUT_FILE"

echo "✅ Converted $INPUT_FILE to $OUTPUT_FILE"
