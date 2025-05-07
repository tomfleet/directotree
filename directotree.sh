#!/bin/bash

SORT_CRITERIA="size"
SHOW_TREE=0
MAX_ROWS=25  # Default limit

while getopts "scatn:" opt; do
    case $opt in
        s) SORT_CRITERIA="size" ;;
        c) SORT_CRITERIA="count" ;;
        a) SORT_CRITERIA="alpha" ;;
        t) SHOW_TREE=1 ;;
        n) MAX_ROWS=$OPTARG ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND -1))

SCAN_PATH="."
[ -n "$1" ] && SCAN_PATH="$1" && shift

# Check for sort argument after path
if [ -n "$1" ]; then
    case "$1" in
        size|count|alpha|-s|-c|-a) 
            case "$1" in
                -s) SORT_CRITERIA="size" ;;
                -c) SORT_CRITERIA="count" ;;
                -a) SORT_CRITERIA="alpha" ;;
                *) SORT_CRITERIA="$1" ;;
            esac
            ;;
        *) echo "Invalid sort criteria: $1. Use 'size', 'count', 'alpha' or -s, -c, -a" >&2; exit 1 ;;
    esac
fi

[ ! -d "$SCAN_PATH" ] && {
    echo "Error: Path '$SCAN_PATH' does not exist or is not a directory." >&2
    exit 1
}

# Use find with printf format for direct size+path output
find "$SCAN_PATH" -type f -printf "%s\t%p\n" | \
awk -v sort_by="$SORT_CRITERIA" -v show_tree=$SHOW_TREE -v max_rows=$MAX_ROWS '
BEGIN {
    total_bytes = 0;
    total_count = 0;
    shown_count = 0;
    RESET="\033[0m";  # Add RESET code definition
    # Pre-calculate unit strings for faster formatting
    units[0] = "B"; units[1] = "KB"; units[2] = "MB"; units[3] = "GB"; units[4] = "TB";
    # Pre-calculate color strings
    for(p = 0; p < 101; p++) {
        if (p < 1) color_cache[p] = "\033[38;2;40;180;40m";
        else if (p < 20) color_cache[p] = sprintf("\033[38;2;40;%d;40m", 180 - (p * 3));
        else if (p < 40) color_cache[p] = sprintf("\033[38;2;40;40;%dm", 180 + ((p - 20) * 3));
        else if (p < 60) color_cache[p] = sprintf("\033[38;2;%d;40;180m", 40 + ((p - 40) * 5));
        else if (p < 80) color_cache[p] = sprintf("\033[38;2;180;40;%dm", 180 - ((p - 60) * 4));
        else color_cache[p] = sprintf("\033[38;2;%d;40;40m", 180 + ((p - 80) * 0.75));
    }
    # Pre-build bar segments
    bar_segment = "■";  # Back to full block
    empty_segment = " ";
}

{
    size = $1
    fullpath = $2
    ext = fullpath
    sub(/.*\./, ".", ext)
    if (ext == fullpath) ext = "(none)"
    
    paths[fullpath] = 1
    split_path(fullpath)  # Get path info for tree view
    
    parent = path_parent[fullpath]
    if (parent) {
        if (!group_sizes[parent]) group_sizes[parent] = 0
        group_sizes[parent] += size
    }
    
    count[ext]++
    bytes[ext] += size
    total_bytes += size
    total_count++

    # Generate sort keys as we go
    if (sort_by == "size") keys[ext] = sprintf("%020d", bytes[ext])
    else if (sort_by == "count") keys[ext] = sprintf("%020d", count[ext])
    else keys[ext] = ext
}

function format_size(size) {
    for(i = 0; size > 1024 && i < 4; i++) {
        size = size/1024;
    }
    if (i == 0) return sprintf("%d%s", size, units[i]);
    return sprintf("%.1f%s", size, units[i]);
}

function make_bar(percent) {
    percent = int(percent);
    color = color_cache[percent];
    max = int((percent * 30) / 100); # Back to 30 chars width
    bar = "";
    
    # Single block rendering
    for(i = 0; i < max; i++)
        bar = bar color bar_segment RESET;
    
    empty = "";
    for(i = max; i < 30; i++)
        empty = empty " ";
    
    return "[" bar empty "]";
}

function bold_if_sorted(text, column) {
    return (column == sort_by) ? BOLD text RESET : text;
}

function split_path(path) {
    if (path in path_cache) return path_name[path];
    
    path_cache[path] = 1;
    gsub(/\\/, "/", path);  # Convert Windows paths
    n = split(path, parts, "/");
    path_depth[path] = n;
    path_name[path] = parts[n];
    path_parent[path] = "";
    
    if (n > 1) {
        parent = parts[1];
        for (i = 2; i < n; i++) {
            parent = parent "/" parts[i];
        }
        path_parent[path] = parent;
    }
    return path_name[path];
}

function make_tree_prefix(path, prefix, p) {
    if (!path_parent[path]) return "";
    p = path_parent[path];
    if (!paths[p]) return "└── ";
    return "├── ";
}

function wrap_output(ext, count, size, pct, bar, wrapped, line_content) {
    if (length(ext) > 15) {
        wrapped = sprintf("%s\n", ext);
        wrapped = wrapped sprintf("%-16s%8d %12s", "└╴", count, size);
        line_content = wrapped;
    } else {
        line_content = sprintf("%-15s %8d %12s", ext, count, size);
    }
    if (sort_by == "size") {
        line_content = sprintf("%s %6.1f%%", line_content, pct);
    } else if (sort_by == "count") {
        line_content = sprintf("%s %6.1f%%", line_content, pct);
    }
    return sprintf("%s %s", line_content, bar);
}

function calc_percent(part, total) {
    return (total > 0) ? (part / total) * 100 : 0;
}

function quicksort(arr, left, right, i, last) {
    if (left >= right)
        return;
    swap(arr, left, int((left + right)/2));
    last = left;
    for (i = left + 1; i <= right; i++) {
        if ((sort_by == "alpha" && keys[arr[i]] < keys[arr[left]]) ||
            (sort_by != "alpha" && keys[arr[i]] > keys[arr[left]])) {
            swap(arr, ++last, i);
        }
    }
    swap(arr, left, last);
    quicksort(arr, left, last - 1);
    quicksort(arr, last + 1, right);
}

function swap(arr, i, j, temp) {
    temp = arr[i];
    arr[i] = arr[j];
    arr[j] = temp;
}

END {
    if (total_count == 0) {
        print "No files found.";
        exit 0;
    }
    
    printf "\nTotal: %s, %d files", format_size(total_bytes), total_count;
    if (max_rows > 0 && total_count > max_rows) {
        printf " (showing top %d)\n", max_rows;
    } else {
        printf "\n";
    }
    
    if (sort_by == "size") {
        printf "%s%-15s %8s %12s %6s%% %30s%s\n",   # Back to 30
               BOLD, "EXT", "COUNT", "SIZE", "SIZE", "", RESET;
        printf "%-15s %8s %12s %6s  %30s\n",         # Back to 30
               "---", "-----", "----", "----", "";
    } else if (sort_by == "count") {
        printf "%s%-15s %8s %6s%% %12s %40s%s\n", 
               BOLD, "EXT", "COUNT", "CNT", "SIZE", "", RESET;
        printf "%-15s %8s %6s %12s %40s\n", 
               "---", "-----", "---", "----", "";
    } else {
        printf "%s%-15s %8s %12s %40s%s\n", 
               BOLD, "EXT", "COUNT", "SIZE", "", RESET;
        printf "%-15s %8s %12s %40s\n", 
               "---", "-----", "----", "";
    }
    
    n = 0;
    for (e in count) {
        size_pct = calc_percent(bytes[e], total_bytes)
        count_pct = calc_percent(count[e], total_count)
        bar_pct = (sort_by == "size") ? size_pct : count_pct
        if (sort_by == "alpha") bar_pct = size_pct
        
        outputs[e] = wrap_output(e, count[e], format_size(bytes[e]), 
                               (sort_by == "size") ? size_pct : 
                               (sort_by == "count") ? count_pct : 0,
                               make_bar(bar_pct))
        sorted_exts[n++] = e  # Build sort array as we go
    }
    
    quicksort(sorted_exts, 0, n-1);
    limit = (max_rows > 0) ? min(max_rows, n) : n;
    for (i = 0; i < limit; i++) {
        print outputs[sorted_exts[i]];
    }
    
    if (show_tree) {
        print "\nDirectory Structure:";
        PROCINFO["sorted_in"] = "@val_str_asc";
        tree_cache[""] = "";  # Initialize root
        
        # First pass - build tree structure
        for (path in paths) {
            curr_parent = path_parent[path];
            if (!tree_cache[curr_parent]) {
                tree_cache[curr_parent] = sprintf("%s [%s]", 
                    curr_parent, format_size(group_sizes[curr_parent]));
            }
        }
        
        # Second pass - display tree
        for (path in tree_cache) {
            if (path) printf "%s\n", tree_cache[path];
        }
        for (path in paths) {
            printf "%s%s\n", make_tree_prefix(path), path_name[path];
        }
    }
}

function min(a, b) {
    return a < b ? a : b;
}
'