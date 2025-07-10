#!/bin/bash

# Description:
# This script generates a dependency tree for a given ELF file, visualizing library dependencies
# in a Graphviz .dot file. Nodes represent libraries with rounded rectangle shapes, bold black
# borders, and group-based background colors, showing the total number of exported functions.
# Edges indicate dependencies with labels showing the number of potentially called functions.
# Edges between same-group modules are bold and black; edges with zero called functions are dashed.
# All text and borders are black, edges (except same-group edges) are dark grey. The output .dot file and
# optional PNG image can be customized via command-line arguments.

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <ELF_file_path> [--depth <depth>] [--group <path>] [--output <dot_file>] [--image <image_file>] [--help]" >&2
    exit 1
fi

# Initialize variables
ELF_FILE="$1"
MAX_DEPTH=999
RGROUPS=()
DOT_FILE="deps.dot"
IMAGE_FILE=""
COLORS=("red" "blue" "green" "purple" "orange" "cyan" "pink" "yellow" "brown" "gray" "magenta" "lime" "teal" "indigo" "violet" "maroon")
GROUP_COLORS=()
DECLARED_NODES=()

# Parse arguments
shift
while [ $# -gt 0 ]; do
    if [ "$1" = "--depth" ]; then
        if [ $# -lt 2 ]; then
            echo "Error: --depth requires an argument" >&2
            exit 1
        fi
        if [[ "$2" =~ ^[0-9]+$ ]]; then
            MAX_DEPTH="$2"
        else
            echo "Error: --depth requires a numeric argument, got: $2" >&2
            exit 1
        fi
        shift 2
    elif [ "$1" = "--group" ]; then
        if [ $# -lt 2 ]; then
            echo "Error: --group requires an argument" >&2
            exit 1
        fi
        if [[ -n "$2" && ! "$2" =~ ^[0-9]+$ ]]; then
            RGROUPS+=("$2")
            GROUP_COLORS+=("${COLORS[${#GROUP_COLORS[@]} % ${#COLORS[@]}]}")
        fi
        shift 2
    elif [ "$1" = "--output" ]; then
        if [ $# -lt 2 ]; then
            echo "Error: --output requires an argument" >&2
            exit 1
        fi
        DOT_FILE="$2"
        shift 2
    elif [ "$1" = "--image" ]; then
        if [ $# -lt 2 ]; then
            echo "Error: --image requires an argument" >&2
            exit 1
        fi
        IMAGE_FILE="$2"
        shift 2
    elif [ "$1" = "--help" ]; then
        echo "Usage: $0 <ELF_file_path> [--depth <depth>] [--group <path>] [--output <dot_file>] [--image <image_file>] [--help]"
        echo "  <ELF_file_path>      Path to the executable ELF file or library"
        echo "  --depth <depth>      Set maximum dependency depth (default: 999)"
        echo "  --group <path>       Specify a path group for background color (e.g., /usr/lib/)"
        echo "  --output <dot_file>  Specify output .dot file (default: deps.dot)"
        echo "  --image <image_file> Generate PNG image at specified path"
        echo "  --help               Show this help message"
        echo "Outputs dependency tree to the specified .dot file and console, with group-based background colors,"
        echo "function counts in nodes, and called functions on edges. Nodes are rounded rectangles with bold black borders."
        echo "Edges between same-group modules are bold and black; edges with zero called functions are dashed."
        echo "All text and borders are black, edges (except same-group edges) are dark grey."
        exit 0
    else
        echo "Unknown argument: $1" >&2
        exit 1
    fi
done

# Resolve absolute path for ELF file
ABS_ELF_FILE=$(realpath "$ELF_FILE" 2>/dev/null)
if [ ! -f "$ABS_ELF_FILE" ]; then
    echo "Error: Could not resolve absolute path for $ELF_FILE or file does not exist" >&2
    exit 1
fi

# Check for nm utility
if ! command -v nm >/dev/null 2>&1; then
    echo "Error: nm utility not found. Function counting is not possible." >&2
    exit 1
fi

# Initialize .dot file
echo "digraph G {" > "$DOT_FILE"
echo "    rankdir=LR;" >> "$DOT_FILE"

# Function to find library path
function find_lib_path {
    local lib="$1"
    local path=$(ldconfig -p | grep -w "$lib" | awk '{print $4}' | head -n 1)
    if [ -n "$path" ] && [ -f "$path" ]; then
        echo "$path"
        return
    fi
    if [ -n "$LD_LIBRARY_PATH" ]; then
        for dir in $(echo "$LD_LIBRARY_PATH" | tr ':' '\n'); do
            if [ -f "$dir/$lib" ]; then
                echo "$dir/$lib"
                return
            fi
        done
    fi
    for dir in /lib /lib64 /usr/lib /usr/lib64 /usr/lib32 /mnt; do
        if [ -f "$dir/$lib" ]; then
            echo "$dir/$lib"
            return
        fi
    done
    local elf_dir=$(dirname "$ABS_ELF_FILE")
    if [ -f "$elf_dir/$lib" ]; then
        echo "$elf_dir/$lib"
        return
    fi
    echo ""
}

# Function to count total functions in a library
function count_functions {
    local file="$1"
    local func_count=0
    if [ -f "$file" ]; then
        # Count exported functions (type T)
        func_count=$(nm -D "$file" 2>/dev/null | grep " T " | wc -l)
        if [ $? -ne 0 ]; then
            func_count=0
        fi
    fi
    echo "$func_count"
}

# Function to count potentially called functions
function count_called_functions {
    local parent_file="$1"
    local dep_file="$2"
    local called_count=0
    if [ -f "$parent_file" ] && [ -f "$dep_file" ]; then
        # Get imported symbols from parent_file
        local parent_imports=$(nm -D --undefined-only "$parent_file" 2>/dev/null | awk '{print $NF}' | sort)
        # Get exported functions (type T) from dep_file
        local dep_exports=$(nm -D --defined-only "$dep_file" 2>/dev/null | grep " T " | awk '{print $NF}' | sort)
        if [ -n "$parent_imports" ] && [ -n "$dep_exports" ]; then
            # Find intersection of imported and exported symbols
            called_count=$(echo -e "$parent_imports\n$dep_exports" | sort | uniq -d | wc -l)
        fi
    fi
    echo "$called_count"
}

# Function to determine group by path
function get_group {
    local file="$1"
    for i in "${!RGROUPS[@]}"; do
        local group="${RGROUPS[$i]}"
        if [[ "$file" == *"$group"* ]]; then
            echo "$i"
            return
        fi
    done
    echo "-1"
}

# Function to get node background color
function get_bg_color {
    local group_idx="$1"
    if [ "$group_idx" -eq -1 ]; then
        echo "white"
    else
        echo "${GROUP_COLORS[$group_idx]}"
    fi
}

# Function to build dependency tree
function print_deps {
    local file="$1"
    local indent="$2"
    local depth="$3"
    local parent="$4"
    if [ "$depth" -le 0 ]; then
        return
    fi
    local file_name=$(basename "$file")
    local node_name=$(echo "$file_name" | sed 's/[^a-zA-Z0-9.]/_/g')
    local group_idx=$(get_group "$file")
    local bg_color=$(get_bg_color "$group_idx")
    local group_name="None"
    if [ "$group_idx" -ne -1 ]; then
        group_name="${RGROUPS[$group_idx]}"
    fi
    local func_count=$(count_functions "$file")
    if [[ ! " ${DECLARED_NODES[@]} " =~ " ${node_name} " ]]; then
        # Add node with rounded rectangle, bold border, and group-based background
        if [ "$func_count" -gt 0 ]; then
            echo "    \"$node_name\" [label=\"${file_name}\\n${file}\\n${func_count} functions\", shape=box, style=\"rounded,filled\", fillcolor=\"$bg_color\", color=black, fontcolor=black, penwidth=2, fontsize=8];" >> "$DOT_FILE"
        else
            echo "    \"$node_name\" [label=\"${file_name}\\n${file}\\nNo functions found\", shape=box, style=\"rounded,filled\", fillcolor=\"$bg_color\", color=black, fontcolor=black, penwidth=2, fontsize=8];" >> "$DOT_FILE"
            echo "${indent}  [WARN] Could not count functions for $file_name" >&2
        fi
        DECLARED_NODES+=("$node_name")
    fi
    if [ -n "$parent" ]; then
        local parent_name=$(basename "$parent" | sed 's/[^a-zA-Z0-9.]/_/g')
        local parent_group_idx=$(get_group "$parent")
        local called_count=$(count_called_functions "$parent" "$file")
        local edge_style="solid"
        local edge_color="darkgrey"
        local edge_width="1"
        local label_color="darkgrey"
        if [ "$called_count" -eq 0 ]; then
            edge_style="dashed"
        fi
        if [ "$group_idx" -eq "$parent_group_idx" ] && [ "$group_idx" -ne -1 ]; then
            edge_color="black"
            edge_width="2"
            label_color="black"
        fi
        echo "    \"$parent_name\" -> \"$node_name\" [label=\"$called_count called\", style=\"$edge_style\", color=\"$edge_color\", penwidth=\"$edge_width\", fontcolor=\"$label_color\", fontsize=8];" >> "$DOT_FILE"
        if [ "$called_count" -eq 0 ] && [ "$edge_style" = "dashed" ]; then
            echo "${indent}  [WARN] No called functions detected for $file_name from $parent" >&2
        fi
    fi
    echo "${indent}${file_name} (bg_color: $bg_color, group: $group_name, path: $file, functions: $func_count)"
    local deps=$(readelf -d "$file" 2>/dev/null | grep NEEDED | awk '{print $5}' | sed 's/\[//;s/\]//')
    for dep in $deps; do
        local dep_path=$(find_lib_path "$dep")
        if [ -n "$dep_path" ] && [ -f "$dep_path" ]; then
            print_deps "$dep_path" "$indent  " $((depth - 1)) "$file"
        else
            echo "${indent}  [WARN] Path not found for $dep" >&2
        fi
    done
}

# Check if file exists
if [ ! -f "$ABS_ELF_FILE" ]; then
    echo "Error: File $ELF_FILE does not exist" >&2
    exit 1
fi

# Build dependency tree with absolute ELF file path
print_deps "$ABS_ELF_FILE" "" "$MAX_DEPTH" ""

# Finalize .dot file
echo "}" >> "$DOT_FILE"

echo "File $DOT_FILE successfully created."

# Generate image if --image is specified
if [ -n "$IMAGE_FILE" ]; then
    if command -v dot >/dev/null 2>&1; then
        dot -Tpng "$DOT_FILE" -o "$IMAGE_FILE"
        if [ $? -eq 0 ]; then
            echo "Image $IMAGE_FILE successfully created."
        else
            echo "Error creating image $IMAGE_FILE" >&2
        fi
    else
        echo "Error: dot command not found. Install Graphviz to generate the image." >&2
    fi
else
    echo "To visualize, use: dot -Tpng $DOT_FILE -o output.png"
fi