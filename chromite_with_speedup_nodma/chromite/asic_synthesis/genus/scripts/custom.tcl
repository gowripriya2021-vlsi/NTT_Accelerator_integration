# see LICENSE.incore
proc getLogicLevel {timingPointsColl} {

set currentInst ""
set pathInstList {}


foreach_in_collection timingPointObj $timingPointsColl {

set pinObj [get_property $timingPointObj pin]
set objType [get_property $pinObj object_type]

if {$objType == "pin"} {
set instObj [get_cell -of_objects $pinObj]
set instName [get_property $instObj hierarchical_name]
} else {
set instName [get_property $pinObj hierarchical_name]
}

if {$instName != $currentInst} {
lappend pathInstList $instName
set currentInst $instName
}
}
set logicLevel [llength $pathInstList]

return $logicLevel
}

################################################################################
# Procedure to generate timing slack file
# Usage: generateSlackReport -mode <setup | hold> -slackTarget <slack_target> -file <report_file>
################################################################################
proc generateSlackReport {args} {


# Defaults
set slackTarget 0.0


# Get setup/hold
if {[regexp {\-mode} $args]} {
set analysisMode [lindex $args [expr [lsearch $args -mode] + 1]]
}


# Get slack target
if {[regexp {\-slackTarget} $args]} {
set slackTarget [lindex $args [expr [lsearch $args -slackTarget] + 1]]
}


# Get slack file name
if {[regexp {\-file} $args]} {
set slackFile [lindex $args [expr [lsearch $args -file] + 1]]
}

# Help
set helpString "Usage : generateSlackReport \
\-mode <setup | hold > \
\-slackTarget <slack_target> \
\-file <slack_file_name> \
\-help"


if {[regexp {\-help} $args] || $args == ""} {
puts $helpString
return 0
}


# Main code 
############################################################


# Open slack report file
set f [open $slackFile w]


# Set command set for setup/hold analysis
if {$analysisMode == "setup"} {

set rptTimingCmd {report_timing -from [all_registers -clock_pins] -to [all_registers -data_pins] -max_slack $slackTarget}

} elseif {$analysisMode == "hold"} {

set rptTimingCmd {report_timing -from [all_registers -clock_pins] -to [all_registers -data_pins] -max_slack $slackTarget}

} else {

puts "ERROR: Unsupported analysis mode!"
return 0
}


# Report header
puts $f [genLine -width 100 -char "="]
puts $f [format "%-10s %-30s %-8s %-8s %-25s %-50s %80s" "Slack" "View Name" "Level" "Skew" "Clock Domain" "Launch Point" "Capture Point"]
puts $f [genLine -width 100 -char "="]

# Create a collection of timing paths
set timingPaths [eval $rptTimingCmd]

if {[sizeof_collection $timingPaths] > 0} {

# Iterate over the set of paths, and process them one at-a-time
foreach_in_collection path [sort_collection $timingPaths {slack}] {

set timingPointsColl [get_property $path timing_points]
set logicDepth [getLogicLevel $timingPointsColl]

set startPoint [get_property [get_property $path launching_point] hierarchical_name]
set endPoint [get_property [get_property $path capturing_point] hierarchical_name]
set launchClock [get_property [get_property $path launching_clock] hierarchical_name]
set captureClock [get_property [get_property $path capturing_clock] hierarchical_name]
set launchClkEdge [lindex [split [get_property $path launching_clock_open_edge_type] {}] 0]
set captureClkEdge [lindex [split [get_property $path capturing_clock_close_edge_type] {}] 0]
set launchClockTime [expr [get_property $path launching_clock_latency] + [get_property $path launching_clock_open_edge_time]]
set captureClockTime [expr [get_property $path capturing_clock_latency] + [get_property $path capturing_clock_close_edge_time]]
set skew [expr abs($captureClockTime - $launchClockTime)]
set slack [get_property $path slack]
set viewName [get_property $path view_name]


puts $f [format "%-10s %-30s %-8s %-8.2f %-25s %-50s %-80s" $slack $viewName $logicDepth $skew "${launchClock}(${launchClkEdge})->${captureClock}(${captureClkEdge})" $startPoint $endPoint]

}
}

close $f
}

################################################################################
# Procedure to generate line seperator
# Usage: genLine -width <width_size> -char <character_name>
# Example: genLine -width 20 -char "#"
################################################################################
proc genLine {args} {

# Default
set char "-"

# Get width
if {[regexp {\-width} $args]} {
set width [lindex $args [expr [lsearch $args -width] + 1]]
}

# Get char
if {[regexp {\-char} $args]} {
set char [lindex $args [expr [lsearch $args -char] + 1]]
}


# Help
set helpString "Usage : genLine -width <width> -char <character>"

if {[regexp {\-help} $args] || $args == ""} {
puts $helpString
return 0
}

# Main code
#########################################################################


for {set i 0} {$i <= $width} {incr i} {
lappend print_list $char
}

return "[join $print_list $char]"
}
