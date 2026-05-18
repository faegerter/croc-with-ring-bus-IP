# ------------------------------------------------------------
# Tree-like area / GE report for flattened i_slink hierarchy
#
# Usage:
#   read_db out/croc.odb
#   source report_slink_area_tree.tcl
#
# Optional knobs before source:
#   set max_depth 4
#   set min_area_um2 10.0
#   set slink_prefix "i_croc_soc/i_user/i_slink"
#   set nand2_ref_cell "sg13g2_nand2_1"
#   set top_x 5
# ------------------------------------------------------------

if {![info exists slink_prefix]} {
    set slink_prefix "i_croc_soc/i_user/i_slink"
}

if {![info exists max_depth]} {
    set max_depth 3
}

if {![info exists min_area_um2]} {
    set min_area_um2 50.0
}

if {![info exists nand2_ref_cell]} {
    set nand2_ref_cell "sg13g2_nand2_1"
}

if {![info exists top_x]} {
    set top_x 5
}

set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]

catch {unset area_by_node}
catch {unset count_by_node}
catch {unset children_by_node}
catch {unset seen_child}
catch {unset master_area_by_name}

array set area_by_node {}
array set count_by_node {}
array set children_by_node {}
array set seen_child {}
array set master_area_by_name {}
set rows {}
set top_rows {}
set terminal_rows {}

proc inst_area_um2 {inst dbu} {
    set master [$inst getMaster]
    set width  [$master getWidth]
    set height [$master getHeight]
    return [expr {double($width) * double($height) / double($dbu * $dbu)}]
}

proc add_area {node area} {
    global area_by_node count_by_node

    if {![info exists area_by_node($node)]} {
        set area_by_node($node) 0.0
        set count_by_node($node) 0
    }

    set area_by_node($node) [expr {$area_by_node($node) + $area}]
    incr count_by_node($node)
}

proc add_child {parent child} {
    global children_by_node seen_child

    set key "$parent|||$child"

    if {![info exists seen_child($key)]} {
        set seen_child($key) 1

        if {![info exists children_by_node($parent)]} {
            set children_by_node($parent) [list]
        }

        lappend children_by_node($parent) $child
    }
}

proc node_depth {node} {
    if {$node eq ""} {
        return 0
    }
    return [llength [split $node "."]]
}

proc print_tree {node indent nand2_area max_depth min_area_um2} {
    global area_by_node count_by_node children_by_node

    if {![info exists area_by_node($node)]} {
        return
    }

    set area $area_by_node($node)

    if {$area < $min_area_um2} {
        return
    }

    set count $count_by_node($node)

    if {$nand2_area > 0.0} {
        set ge [expr {$area / $nand2_area}]
        set ge_str [format "%.1f" $ge]
    } else {
        set ge_str "-"
    }

    if {$indent == 0} {
        set label $node
    } else {
        set label "[string repeat "  " [expr {$indent - 1}]]- [lindex [split $node "."] end]"
    }

    puts [format "%12.3f %12s %10d  %s" $area $ge_str $count $label]

    if {$indent >= $max_depth} {
        return
    }

    if {![info exists children_by_node($node)]} {
        return
    }

    set child_rows {}
    foreach child $children_by_node($node) {
        if {[info exists area_by_node($child)]} {
            lappend child_rows [list $area_by_node($child) $child]
        }
    }

    set child_rows [lsort -real -decreasing -index 0 $child_rows]

    foreach row $child_rows {
        set child [lindex $row 1]
        print_tree $child [expr {$indent + 1}] $nand2_area $max_depth $min_area_um2
    }
}

# ------------------------------------------------------------
# Find NAND2 area from cells actually present in the design.
# ------------------------------------------------------------

set nand2_area_um2 0.0

foreach inst [$block getInsts] {
    set master [$inst getMaster]
    set mname [$master getName]

    if {$mname eq $nand2_ref_cell} {
        set nand2_area_um2 [inst_area_um2 $inst $dbu]
        break
    }
}

if {$nand2_area_um2 == 0.0} {
    puts "WARNING: reference NAND2 cell '$nand2_ref_cell' not found in placed instances."
    puts "Available NAND-like cells present in design:"

    array set seen_nand {}
    foreach inst [$block getInsts] {
        set master [$inst getMaster]
        set mname [$master getName]

        if {[string match "*nand*" $mname] && ![info exists seen_nand($mname)]} {
            set seen_nand($mname) 1
            puts [format "  %-30s area_um2=%.3f" $mname [inst_area_um2 $inst $dbu]]
        }
    }
}

# ------------------------------------------------------------
# Build cumulative pseudo-tree from flattened instance names.
# ------------------------------------------------------------

set total_area_um2 0.0
set total_count 0

foreach inst [$block getInsts] {
    set name [$inst getName]

    if {![string match "${slink_prefix}*" $name]} {
        continue
    }

    set area_um2 [inst_area_um2 $inst $dbu]
    set total_area_um2 [expr {$total_area_um2 + $area_um2}]
    incr total_count

    # Remove prefix.
    set rest [string range $name [string length $slink_prefix] end]
    set rest [string trimleft $rest "./"]

    if {$rest eq ""} {
        continue
    }

    # Convert slash hierarchy below i_slink into dot hierarchy.
    regsub -all {/} $rest "." rest

    # Split on dots. This handles names such as:
    #   i_serial_link_data_link.i_raw_mode_fifo.mem_q_119__reg
    #   gen_phy_channels[0].i_serial_link_physical...
    set parts [split $rest "."]

    set parent ""
    set node ""

    set n_parts [llength $parts]
    for {set i 0} {$i < $n_parts && $i < $max_depth} {incr i} {
        set part [lindex $parts $i]

        if {$part eq ""} {
            continue
        }

        if {$node eq ""} {
            set node $part
        } else {
            set node "${node}.${part}"
        }

        add_area $node $area_um2

        if {$parent ne ""} {
            add_child $parent $node
        }

        set parent $node
    }
}

# ------------------------------------------------------------
# Print report.
# ------------------------------------------------------------

puts ""
puts "============================================================"
puts "Tree area report for $slink_prefix"
puts "Max depth:       $max_depth"
puts "Min area shown:  $min_area_um2 um^2"
puts "Total cells:     $total_count"
puts [format "Total area:      %.3f um^2" $total_area_um2]

if {$nand2_area_um2 > 0.0} {
    puts [format "NAND2 ref cell:  %s" $nand2_ref_cell]
    puts [format "NAND2 area:      %.3f um^2" $nand2_area_um2]
    puts [format "Total GE:        %.1f" [expr {$total_area_um2 / $nand2_area_um2}]]
} else {
    puts "Total GE:        unavailable"
}

puts "============================================================"
puts [format "%12s %12s %10s  %s" "Area_um2" "GE" "Cells" "Group"]
puts "------------------------------------------------------------"

# Top-level nodes: nodes with no dot.
set top_rows {}
foreach node [array names area_by_node] {
    if {![string match "*.*" $node]} {
        lappend top_rows [list $area_by_node($node) $node]
    }
}

set top_rows [lsort -real -decreasing -index 0 $top_rows]

foreach row $top_rows {
    set node [lindex $row 1]
    print_tree $node 0 $nand2_area_um2 $max_depth $min_area_um2
}



# ------------------------------------------------------------
# Print top X biggest terminal reported nodes only.
# A node is reported here only if it has no child that also
# passes min_area_um2. This avoids printing both parent and child.
# ------------------------------------------------------------

set terminal_rows {}

foreach node [array names area_by_node] {
    set area $area_by_node($node)

    if {$area < $min_area_um2} {
        continue
    }

    set has_big_child 0

    if {[info exists children_by_node($node)]} {
        foreach child $children_by_node($node) {
            if {[info exists area_by_node($child)] && $area_by_node($child) >= $min_area_um2} {
                set has_big_child 1
                break
            }
        }
    }

    # Skip parents. Keep only deepest/significant children.
    if {$has_big_child} {
        continue
    }

    set count $count_by_node($node)

    if {$nand2_area_um2 > 0.0} {
        set ge [expr {$area / $nand2_area_um2}]
    } else {
        set ge 0.0
    }

    lappend terminal_rows [list $area $ge $count $node]
}

set terminal_rows [lsort -real -decreasing -index 0 $terminal_rows]

puts ""
puts "============================================================"
puts "Top $top_x biggest terminal nodes under $slink_prefix"
puts "============================================================"
puts [format "%12s %12s %10s  %s" "Area_um2" "GE" "Cells" "Full group"]
puts "------------------------------------------------------------"

set printed 0

foreach row $terminal_rows {
    if {$printed >= $top_x} {
        break
    }

    set area  [lindex $row 0]
    set ge    [lindex $row 1]
    set count [lindex $row 2]
    set node  [lindex $row 3]

    if {$nand2_area_um2 > 0.0} {
        puts [format "%12.3f %12.1f %10d  %s" $area $ge $count $node]
    } else {
        puts [format "%12.3f %12s %10d  %s" $area "-" $count $node]
    }

    incr printed
}