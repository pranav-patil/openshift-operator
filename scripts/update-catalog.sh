#!/bin/bash

set -euo pipefail

CATALOG_TEMPLATE=${1:-}
BUNDLE_IMGS=${2:-}
CHANNEL=${3:-alpha}
YQ=${4:-./bin/yq}

if [[ -z "$CATALOG_TEMPLATE" ]]; then
    echo "Error: $CATALOG_TEMPLATE is required. Please provide a valid catalog template path." >&2
    exit 1
fi

if [[ ! -s "$CATALOG_TEMPLATE" ]]; then
    echo "Error: $CATALOG_TEMPLATE file is empty. Please provide a valid catalog template file." >&2
    exit 1
fi

if [[ -z "$BUNDLE_IMGS" ]]; then
    echo "Error: $BUNDLE_IMGS is required. Please provide at least one image in the format 'image:tag' or 'image:tag,image:tag'" >&2
    exit 1
fi

if [[ -z "$CHANNEL" ]]; then
    echo "Error: $CHANNEL is required. Please provide a valid channel name, valid values are `alpha`, `stable`." >&2
    exit 1
fi

if ! [[ "$BUNDLE_IMGS" =~ ^[^:]+:[^:,]+([,][^:]+:[^:,]+)*$ ]]; then
    echo "Error: Invalid $BUNDLE_IMGS format. Expected format: 'image:tag' or 'image:tag,image:tag,...'" >&2
    echo "Got: $BUNDLE_IMGS" >&2
    exit 1
fi

YQ_VERSION=$($YQ --version | grep -o 'version.*' | cut -d' ' -f2)
if [[ ! "$YQ_VERSION" =~ ^v?4\. ]]; then
    echo "Error: YQ version 4.x.x is required. Found version: $YQ_VERSION" >&2
    exit 1
fi

##
# Compares two semantic version strings.
# Usage: vercomp <ver1> <op> <ver2>
# Operators: '>' '<' '>=' '<=' '=='
# Exits with 0 (true) or 1 (false).
##
function vercomp {
    local ver1="$1" op="$2" ver2="$3"
    case $op in
        '>')
            [[ "$(printf '%s\n' "$ver1" "$ver2" | sort -V | tail -n 1)" == "$ver1" && "$ver1" != "$ver2" ]]
            ;;
        '<')
            [[ "$(printf '%s\n' "$ver1" "$ver2" | sort -V | tail -n 1)" == "$ver2" && "$ver1" != "$ver2" ]]
            ;;
        '>=')
            [[ "$(printf '%s\n' "$ver1" "$ver2" | sort -V | tail -n 1)" == "$ver1" ]]
            ;;
        '<=')
            [[ "$(printf '%s\n' "$ver1" "$ver2" | sort -V | tail -n 1)" == "$ver2" ]]
            ;;
        '==')
            [[ "$ver1" == "$ver2" ]]
            ;;
        *)
            echo "Error: Invalid operator '$op' in vercomp function." >&2
            return 2
            ;;
    esac
}

function add_bundle {
    local catalog_path=${1?Pass catalog template path as arg[1]}
    local img=${2?Pass operator bundle image url as arg[2]}
    
    tag="${img##*:}"
    operator_version="${tag#v}"

    if [[ -z "$catalog_path" ]]; then
        echo "Error: Missing file path argument for add_bundle." >&2
        return 1
    fi
    if [[ ! -f "$catalog_path" ]]; then
        echo "Error: File not found at '$catalog_path'." >&2
        return 1
    fi

    local bundle_exists=$($YQ e ".entries[] | select(.schema == \"olm.bundle\" and .image == \"$img\")" "$catalog_path")

    if [[ -z "$bundle_exists" ]]; then
        $YQ -i e "
            select(.schema == \"olm.template.basic\").entries += [{
                \"schema\": \"olm.bundle\",
                \"image\": \"$img\"
            }]" "$catalog_path"
        echo "✅ Bundle entry for version ${operator_version} added."
    else
        echo "ℹ️  Bundle entry for version ${operator_version} already exists. No changes made."
    fi
}

function add_channel {
    local catalog_path=${1?Pass catalog template path as arg[1]}
    local channel_name=${2?Pass channel name as arg[2]}
    local img=${3?Pass operator bundle image url as arg[3]}

    if [[ -z "$catalog_path" || -z "$channel_name" ]]; then
        echo "Error: Missing arguments for add_channel. Usage: add_channel <catalog_path> <channel_name>" >&2
        return 1
    fi
    if [[ ! -f "$catalog_path" ]]; then
        echo "Error: File not found at '$catalog_path'." >&2
        return 1
    fi

    local package_name=$($YQ e '.entries[] | select(.schema == "olm.package") | .name' "$catalog_path")
    tag="${img##*:}"
    operator_version="${tag#v}" # strip leading v
    new_bundle_entry="${package_name}.v${operator_version}"

    local operator_version_exists=$($YQ e ".entries[] | select(.schema == \"olm.channel\" and .name == \"$channel_name\") | .entries[] | select(.name == \"$new_bundle_entry\")" "$catalog_path")

    if [[ -n "$operator_version_exists" ]]; then
        echo "ℹ️  Channel entry for version ${operator_version} already exists in channel '${channel_name}'. No changes made."
        return 0
    fi

    local latest_version=$($YQ e ".entries[] | select(.schema == \"olm.channel\" and .name == \"$channel_name\") | .entries[].name" "$catalog_path" 2>/dev/null | sed 's/.*\.v//' | sort -V | tail -n 1)
    echo "Detected latest operator version: $latest_version"

    if [[ -n "$latest_version" ]]; then
        if vercomp "$operator_version" '<=' "$latest_version"; then
            echo "Error: operator_version ($operator_version) must be greater than the latest version ($latest_version) in channel '${channel_name}'." >&2
            return 1
        fi
    fi

    echo "✨ Adding entry for ${operator_version} to channel '${channel_name}'..."
    if [[ -n "$latest_version" ]]; then
        # If a version exists, the new entry replaces the latest one.
        local latest_bundle_entry="${package_name}.v${latest_version}"
        $YQ -i e "
            select(.schema == \"olm.template.basic\").entries[] |=
                select(.schema == \"olm.channel\" and .name == \"$channel_name\").entries += [{
                    \"name\": \"$new_bundle_entry\",
                    \"replaces\": \"$latest_bundle_entry\"
                }]" "$catalog_path"
        echo "✅ Channel entry for version ${operator_version} replacing ${latest_version} added for channel '${channel_name}'."
    else
        # If the channel is empty, add the first entry without a 'replaces' key.
        $YQ -i e "
            select(.schema == \"olm.template.basic\").entries[] |=
                select(.schema == \"olm.channel\" and .name == \"$channel_name\").entries += [{
                    \"name\": \"$new_bundle_entry\"
                }]" "$catalog_path"
        echo "✅ Initial bundle entry ${operator_version} added to empty channel."
    fi
}

# Add default entry to the channel name if entries are empty
add_channel_default_entry() {
  echo "OPERATOR_VERSION=${OPERATOR_VERSION}"
  local catalog_path=${1?Pass catalog template path as arg[1]}
  local channel_name=${2?Pass channel name as arg[2]}

  local package_name=$($YQ e '.entries[] | select(.schema == "olm.package") | .name' "$catalog_path")
  new_bundle_entry="${package_name}.v$OPERATOR_VERSION"
  local channel_path=".entries[] | select(.schema == \"olm.channel\" and .name == \"$channel_name\")"

  if $YQ "$channel_path.entries | length" "$catalog_path" | grep -q "0"; then
    echo "Entries for channel '$channel_name' are empty. Adding default entry."
    $YQ -i e "
        select(.schema == \"olm.template.basic\").entries[] |=
            select(.schema == \"olm.channel\" and .name == \"$channel_name\").entries += [{
                \"name\": \"$new_bundle_entry\"
            }]" "$catalog_path"
  else
    echo "Entries for channel '$channel_name' are not empty. Skipping."
  fi
}

add_channel_default_entry "$CATALOG_TEMPLATE" "stable"

IFS=',' read -ra images <<< "$BUNDLE_IMGS"
for img in "${images[@]}"; do
    add_channel "$CATALOG_TEMPLATE" "$CHANNEL" "$img"
    add_bundle "$CATALOG_TEMPLATE" "$img"
done

echo "Catalog template updated successfully!"
