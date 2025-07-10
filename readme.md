# ELF Dependency Tree Visualizer

This Bash script generates a dependency tree for a given ELF (Executable and Linkable Format) file, such as an executable or shared library, and visualizes it using Graphviz. The output is a `.dot` file describing the dependency graph, with optional PNG image generation. The script provides detailed information about libraries, including the number of exported functions and potentially called functions between dependencies.

## Features
- **Dependency Tree**: Builds a tree of library dependencies using `readelf` to extract `NEEDED` entries.
- **Function Counting**: Counts exported functions in each library using `nm -D` (symbols of type `T`).
- **Called Functions**: Estimates potentially called functions by intersecting imported symbols (from `nm -D --undefined-only`) and exported functions (from `nm -D --defined-only`).
- **Visual Styling**:
  - Nodes are rounded rectangles with bold black borders (`penwidth=2`) and group-based background colors.
  - Node text and borders are black (`black`).
  - Edges are dark grey, with labels showing the number of potentially called functions.
  - Edges between same-group modules are bold and black (`penwidth=2`) with black labels.
  - Edges with zero called functions are dashed.
- **Custom Outputs**: Supports user-specified paths for `.dot` file (`--output`) and PNG image (`--image`).
- **Group Coloring**: Assigns background colors to nodes based on path groups, with 16 available colors (e.g., red, blue, green).
- **Console Output**: Displays dependency details, including paths, groups, background colors, and function counts.
- **Error Handling**: Provides warnings for missing libraries, failed function counts, or unavailable tools.

## Requirements
- **Bash**: The script runs in a Bash environment.
- **readelf**: To extract library dependencies from ELF files.
- **nm**: To count exported and imported symbols for function analysis.
- **ldconfig**: To locate library paths via the system cache.
- **Graphviz** (optional): Required for PNG image generation (install `dot` command).
- **Linux System**: The script is designed for ELF files, typically found on Linux systems (e.g., Debian, Ubuntu, CentOS, RHEL, Arch Linux).

## Installation
1. Save the script as `elf_deps.sh` (or any preferred name).
2. Make it executable:
   ```bash
   chmod +x elf_deps.sh
3. Ensure dependencies are installed:
```bash
sudo apt-get install binutils graphviz  # On Debian/Ubuntu
sudo yum install binutils graphviz     # On CentOS/RHEL
sudo pacman -S binutils graphviz       # On Arch Linux
```
## Usage
Run the script with an ELF file path and optional arguments:
```bash
./elf_deps.sh <ELF_file_path> [--depth <depth>] [--group <path>] [--output <dot_file>] [--image <image_file>] [--help]
```
### Arguments
- **<ELF_file_path>**: Path to the ELF file (executable or library).
- **--depth <depth>**: Maximum dependency depth (default: 999).
- **--group <path>**: Path prefix for grouping libraries with a specific background color (e.g., /usr/lib/).
- **--output <dot_file>**: Output path for the .dot file (default: deps.dot).
- **--image <image_file>**: Output path for the PNG image. If specified, the image is generated automatically.
- **--help**: Display help message.
### Examples
```bash
./elf_deps.sh /bin/ls
./elf_deps.sh /bin/ls --output custom.dot --image custom.png
./elf_deps.sh /bin/ls --depth 2 --group /usr/lib --group /lib --image deps.png
./elf_deps.sh --help
```
## Output format
- **Console**: Lists each library with its name, background color, group, path, and exported function count. Warnings are shown for missing libraries, failed function counts, or zero called functions.
- **.dot** File: Graphviz-compatible file with:
Nodes as rounded rectangles with bold black borders and group-based background colors.
Node labels showing library name, path, and function count, with black text.
Edges with dark grey color and labels, except for same-group edges (bold and black with black labels).
Dashed edges for dependencies with zero called functions.
- **PNG Image** (if --image is specified): Visual representation of the dependency tree.
## Limitations
- **Function Counting**: Relies on nm -D for exported functions, which may fail for stripped binaries (no symbols).
- **Called Functions**: The count is an approximation based on symbol intersection, not actual function calls. For precise analysis, use disassemblers (objdump -d) or tracing tools (ltrace).
- **Graphviz Rendering**: Complex graphs may have layout issues, especially with many dependencies.
- **File Paths**: If --output or --image paths are invalid (e.g., non-existent directories), errors may occur during file writing.
## License
This script is provided under the MIT License. See LICENSE for details.
