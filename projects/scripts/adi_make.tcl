## ***************************************************************************
## ***************************************************************************
## Copyright 2014 - 2018 (c) Analog Devices, Inc. All rights reserved.
##
## In this HDL repository, there are many different and unique modules, consisting
## of various HDL (Verilog or VHDL) components. The individual modules are
## developed independently, and may be accompanied by separate and unique license
## terms.
##
## The user should read each of these license terms, and understand the
## freedoms and responsibilities that he or she has by using this source/core.
##
## This core is distributed in the hope that it will be useful, but WITHOUT ANY
## WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
## A PARTICULAR PURPOSE.
##
## Redistribution and use of source or resulting binaries, with or without modification
## of this file, are permitted under one of the following two license terms:
##
##   1. The GNU General Public License version 2 as published by the
##      Free Software Foundation, which can be found in the top level directory
##      of this repository (LICENSE_GPL2), and also online at:
##      <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
##
## OR
##
##   2. An ADI specific BSD license, which can be found in the top level directory
##      of this repository (LICENSE_ADIBSD), and also on-line at:
##      https://github.com/analogdevicesinc/hdl/blob/master/LICENSE_ADIBSD
##      This will allow to generate bit files and not release the source code,
##      as long as it attaches to an ADI device.
##
## ***************************************************************************
## ***************************************************************************

##############################################################################
## The folowing procedures are available:
##
## adi_make_lib <args>
##               -"all"(project libraries)
##               -"library name to build (plus path to it relative to library folder)
##                  e.g.: adi_make_lib xilinx/util_adxcvr
## adi_make_boot_bin - expected that u-boot*.elf (plus bl31.elf for zynq_mp)
##                     files are in the project folder"
## For more info please see: https://wiki.analog.com/resources/fpga/docs/build


# library build procedure
proc adi_make_lib { libraries } {

  variable ad_make_env::library_dir
  variable ad_make_env::build_list
  variable ad_make_env::PWD

  if { $libraries == "all" } {
    ad_make_env::get_local_lib
    set libraries $build_list
  }

  set build_list ""
  set space " "
  puts "Building:"
  foreach b_lib $libraries {
    puts "- $b_lib"
    append build_list $library_dir/$b_lib$space
  }

  puts "Please wait, this might take a few minutes"
  ad_make_env::init_build $build_list ;# run in command line mode, with arguments
  cd $PWD
}

# boot_bin build procedure
proc adi_make_boot_bin {} {

  variable ad_make_env::root_hdl_folder
  set arm_tr_sw_elf "bl31.elf"
  set boot_bin_folder "boot_bin"
  set uboot_elf "u-boot.elf"
  catch { set uboot_elf "[glob "./u-boot*.elf"]" } err
  catch { set hdf_file "[glob "./*.sdk/system_top.hdf"]" } err

  puts "root_hdl_folder $root_hdl_folder"
  puts "uboot_elf $uboot_elf"
  puts "hdf_file $hdf_file"

  # Xilinx SDK
  package require platform
  set os_type [platform::generic]
  if { [regexp ^win $os_type] } {
      set w_cmd where
  } elseif { [regexp ^linux $os_type] } {
      set w_cmd which
  } else {
    puts "ERROR: Unknown OS: $os_type"
    return
  }
  set xsct_loc [exec $w_cmd xsct]

  # search for Xilinx Command Line Tool (SDK)
  if { $xsct_loc == "" } {
     puts $env(PATH)
     puts "ERROR: SDK not installed or it is not defined in the enviroment path"
     return
  }

  set xsct_script "exec xsct $root_hdl_folder/projects/scripts/adi_make_boot_bin.tcl"
  set build_args "$hdf_file $uboot_elf $boot_bin_folder $arm_tr_sw_elf"
  puts "Please wait, this may take a few moments."
  eval $xsct_script $build_args
}

namespace eval ad_make_env {
  ##############################################################################
  # to print build step messages "set msg_level=1" (set ad_make_env::msg_level 1)
  variable msg_level 0
  ##############################################################################

  # global variables
  variable build_list
  variable library_dir
  variable PWD
  variable root_hdl_folder
  variable done_list
  variable serch_pattern


  # init local namespace variables
  set build_list ""
  set match ""
  set PWD [pwd]
  set done_list ""
  set depend_lib ""
  set match ""

  # define library dependency search (Makefiles)
  set serch_pattern "XILINX_.*_DEPS.*="


  # get library absolute path
  set root_hdl_folder ""
  set glb_path $PWD
  if { [regexp projects $glb_path] } {
    regsub {/projects.*$} $glb_path "" root_hdl_folder
  } else {
    puts "ERROR: Not in hdl/* folder"
    return
  }

  set library_dir "$root_hdl_folder/library"

  ##############################################################################
  # have debug messages
  proc puts_msg_level { message } {
    variable msg_level
    if { $msg_level == 1 } {
      puts $message
    }
  }

  ##############################################################################
  # search for project IP dependencies
  proc get_local_lib {} {

    variable library_dir
    variable build_list

    set search_pattern "LIB_DEPS.*="
    set match ""
    set fp1 [open ./Makefile r]
    set file_data [read $fp1]
    close $fp1

    set lines [split $file_data \n]
    foreach line $lines {
      regexp $search_pattern $line match
      if { $match != "" } {
        regsub -all $search_pattern $line "" library
        set library [string trim $library]
        puts_msg_level "    - dependency library $library"
        append build_list "$library "
        set match ""
      }
    }
  }

  ##############################################################################
  # search for library IP dependencies
  proc search_ip_dependency { path } {

    # global variables
    variable serch_pattern
    variable library_dir

    puts_msg_level "DEBUG search_ip_dependency proc"

    set match ""
    set fp1 [open $library_dir/$path/Makefile r]
    set file_data [read $fp1]
    close $fp1

    set lines [split $file_data \n]
    foreach line $lines {
      regexp $serch_pattern $line match
      if { $match != "" } {
        regsub -all $serch_pattern $line "" lib_dep
        set lib_dep [string trim $lib_dep]
        puts_msg_level "    > dependency library $lib_dep"
        # build dependency
        build_dep_lib $lib_dep
        set match ""
      }
    }
  }

  ##############################################################################
  # build procedure
  proc build_dep_lib { library } {

    # global variables
    variable done_list
    variable library_dir

    puts_msg_level "DEBUG build_dep_lib proc"

    # determine if the IP was previously built in the current adi_make_lib.tcl call
    if { [regexp $library $done_list] } {
      puts_msg_level "Build previously done on $library"
      return
    } else {
      puts_msg_level "- Start build of $library"
    }
    puts_msg_level "- Search dependencies for $library"

    # search for current IP dependencies
    search_ip_dependency $library

    puts_msg_level "- Continue build on $library"
    set ip_name "[file tail $library]_ip"

    cd $library_dir/${library}
    exec vivado -mode batch -source "$library_dir/${library}/${ip_name}.tcl"
    file copy -force ./vivado.log ./${ip_name}.log
    puts "- Done building $library"
    append done_list $library
  }

  ##############################################################################
  # search for sub dir ips and start build
  proc init_build { ips } {

    set makefiles ""
    # searching for subdir libraries in path for first argument
    set first_lib [lindex $ips 0]
    if { $first_lib == "" } {
     set first_lib "."
    }
    # getting all parsed arguments (libraries)
    set index 0
    set library_element(1) $first_lib
    foreach argument $ips {
     incr index 1
     set library_element($index) $argument
    }

    # search for all possible IPs in the given argument paths
    if { $index == 0 } {
      set index 1
    }
    for {set y 1} {$y<=$index} {incr y} {
      set dir "$library_element($y)/"
      #search 4 level subdirectories for Makefiles
      for {set x 1} {$x<=4} {incr x} {
      catch { append makefiles " [glob "${dir}Makefile"]" } err
        append dir "*/"
      }
    }

    if { $makefiles == "" } {
      puts "ERROR: Wrong path to IP or the IP does not have a Makefile starting from \"$library_element(1)\""
    }

    # filter out non buildable libs (non *_ip.tcl)
    set buildable ""
    foreach fs $makefiles {
      set ip_dir [file dirname $fs]
      set ip_name "[file tail $ip_dir]_ip.tcl"
      if { [file exists $ip_dir/$ip_name] } {
        append buildable "$fs "
      }
    }
    set makefiles $buildable

    # build all detected IPs
    foreach fs $makefiles {
      regsub /Makefile $fs "" fs
      if { $fs == "." } {
        set fs [file normalize $fs]
        set fs [file tail $fs]
        set fs [string trim $fs]
      }
      regsub .*library/ $fs "" fs
      build_dep_lib $fs
    }
  }
} ;# ad_make_env namespace


#############################################################################
#############################################################################
