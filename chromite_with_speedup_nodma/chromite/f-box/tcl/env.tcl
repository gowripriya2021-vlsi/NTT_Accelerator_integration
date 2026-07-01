global home_dir
global fpga_dir
global core_project_dir

# set different directories as variables
set home_dir [exec pwd]
set fpga_dir $home_dir/build/hw/fpga
set core_project_dir $home_dir/build/fbox/

# set ip project name
set core_project fbox
puts "\nDEBUG: home_dir:        $home_dir"
puts "DEBUG: fpga_dir:          $fpga_dir"
puts "DEBUG: core_project_dir:  $core_project_dir"
