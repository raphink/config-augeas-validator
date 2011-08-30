(*
Module: FAI_DiskConfig
 Parses disk_config files for FAI

Author: Raphael Pinson <raphink@gmail.com>

About: Reference
 This lens tries to keep as close as possible to the FAI wiki where possible:
 http://wiki.fai-project.org/wiki/Setup-storage#New_configuration_file_syntax

About: License
  This file is licensed under the LGPLv2+, like the rest of Augeas.

About: Lens Usage
*)

module FAI_DiskConfig =

autoload xfm

(************************************************************************
 * Group:                 USEFUL PRIMITIVES
 *************************************************************************)

(* Group: Generic primitives *)
(* Variable: eol *)
let eol = Util.eol

(* Variable: space *)
let space = Sep.space

(* Variable: empty *)
let empty = Util.empty

(* Variable: comment *)
let comment = Util.comment

(************************************************************************
 * Group:                      RECORDS
 *************************************************************************)


(* Group: volume *)

(* Variable: mountpoint_kw *)
let mountpoint_kw = "-" (* do not mount *)
         | "swap"       (* swap space *)
         (* fully qualified path; if :encrypt is given, the partition
          * will be encrypted, the key is generated automatically *)
         | /\/[^ \t\n]*(:encrypt)?/

(* Variable: mountpoint *)
let mountpoint = [ label "mountpoint" . store mountpoint_kw ]

let resize = [ Util.del_str ":" . key "resize" ]

let size_kw = /[0-9]+[kMGTP%]?(-([0-9]+[kMGTP%]?)?)?/
            | /-[0-9]+[kMGTP%]?/

(* Variable: size *)
let size = [ label "size" . store size_kw . resize? ]

let filesystem_kw = "-"
         | "swap"
         | (Rx.no_spaces - "-" - "swap") (* mkfs.xxx must exist *)

let filesystem = [ label "filesystem" . store filesystem_kw ]


let mount_option_value = [ label "value" . Util.del_str "="
                         . store /[^,= \t\n]+/ ]

let mount_option = [ seq "mount_option"
                   . store /[^,= \t\n]+/
                   . mount_option_value? ]

let mount_options = [ label "mount_options"
                    . counter "mount_option"
                    . Build.opt_list mount_option Sep.comma ]

let fs_option = 
     [ key /createopts|tuneopts/
     . Util.del_str "=\"" . store /[^"\n]*/ . Util.del_str "\"" ]

let fs_options =
     (* options to append to mkfs.xxx and to the filesystem-specific
      * tuning tool *)
     [ label "fs_options" . Build.opt_list fs_option Sep.space ]

let volume_full (type:lens) (third_field:lens) =
           [ type . space
           . mountpoint .space
           . third_field . space
           . filesystem . space
           . mount_options
           . (space . fs_options)? ]

let type_label (kw:regexp) = key kw

let name = [ label "name" . store /[^\/ \t\n]+/ ] (* lvm volume group name *)

let partition = [ label "partition" . Util.del_str "." . store /[0-9]+/ ]

let disk = [ label "disk" . store /[^\., \t\n]+/ . partition? ]


let vg_option = 
     [ key "pvcreateopts"
     . Util.del_str "=\"" . store /[^"\n]*/ . Util.del_str "\"" ]

let volume_vg = [ key "vg"
                . space . name
                . space . disk
                . (space . vg_option)? ]

let spare_missing = [ Util.del_str ":" . key /spare|missing/ ]

let disk_with_opt = [ label "disk" . store /[^:\., \t\n]+/ . partition?
                    . spare_missing* ]

let disk_list = Build.opt_list disk_with_opt Sep.comma

let type_label_lv = label "lv"
                    . [ label "vg" . store (/[^# \t\n-]+/ - "raw") ]
                    . Util.del_str "-"
                    . [ label "name" . store /[^ \t\n]+/ ]

let volume_tmpfs = 
           [ key "tmpfs" . space
           . mountpoint .space
           . size . space
           . mount_options
           . (space . fs_options)? ]

(* TODO: assign each volume type to a specific disk_config type *)
let volume_entry = volume_full (type_label "primary") size     (* for physical disks only *)
                 | volume_full (type_label "logical") size     (* for physical disks only *)
                 | volume_full (type_label /raid[0156]/) disk_list  (* raid level *)
                 | volume_full (type_label "raw-disk") size
                 | volume_full type_label_lv size  (* lvm logical volume: vg name and lv name *)
                 | volume_vg
                 | volume_tmpfs

let volume = volume_entry . eol

let volume_or_comment = 
      volume | (volume . (volume|empty|comment)* . volume)

(* Group: disk_config *)
let disk_config_entry (kw:regexp) (opt:lens) =
                  [ key "disk_config" . space . store kw
                  . (space . opt)* . eol
                  . volume_or_comment? ]

let generic_opt (type:string) (kw:regexp) =
   [ key type . Util.del_str ":" . store kw ]

let lvmoption =
     (* preserve partitions -- always *)
      generic_opt "preserve_always" /[^\/, \t\n-]+-[^\/, \t\n-]+(,[^\/,\s\-]+-[^\/, \t\n-]+)*/
     (* preserve partitions -- unless the system is installed
      * for the first time *)
   | generic_opt "preserve_reinstall" /[^\/, \t\n-]+-[^\/, \t\n-]+(,[^\/, \t\n-]+-[^\/, \t\n-]+)*/
     (* attempt to resize partitions *)
   | generic_opt "resize" /[^\/, \t\n-]+-[^\/, \t\n-]+(,[^\/, \t\n-]+-[^\/, \t\n-]+)*/
     (* when creating the fstab, the key used for defining the device
      * may be the device (/dev/xxx), a label given using -L, or the uuid *)
   | generic_opt "fstabkey" /device|label|uuid/

let raidoption =
     (* preserve partitions -- always *)
     generic_opt "preserve_always" /[0-9]+(,[0-9]+)*/
     (* preserve partitions -- unless the system is installed
      * for the first time *)
   | generic_opt "preserve_reinstall" /[0-9]+(,[0-9]+)*/
     (* when creating the fstab, the key used for defining the device
      * may be the device (/dev/xxx), a label given using -L, or the uuid *)
   | generic_opt "fstabkey" /device|label|uuid/

let option =
     (* preserve partitions -- always *)
     generic_opt "preserve_always" /[0-9]+(,[0-9]+)*/
     (* preserve partitions -- unless the system is installed
        for the first time *)
   | generic_opt "preserve_reinstall" /[0-9]+(,[0-9]+)*/
     (* attempt to resize partitions *)
   | generic_opt "resize" /[0-9]+(,[0-9]+)*/
     (* write a disklabel - default is msdos *)
   | generic_opt "disklabel" /msdos|gpt/
     (* mark a partition bootable, default is / *)
   | generic_opt "bootable" Rx.integer
     (* do not assume the disk to be a physical device, use with xen *)
   | [ key "virtual" ]
     (* when creating the fstab, the key used for defining the device
      * may be the device (/dev/xxx), a label given using -L, or the uuid *)
   | generic_opt "fstabkey" /device|label|uuid/

let disk_config =
    let other_label = Rx.fspath - "lvm" - "raid" - "end" - /disk[0-9]+/ in
                  disk_config_entry "lvm" lvmoption
                | disk_config_entry "raid" raidoption
                | disk_config_entry "end" option (* there shouldn't be an option here *)
                | disk_config_entry /disk[0-9]+/ option
                | disk_config_entry other_label option

let lns = (disk_config|comment|empty)*


let xfm = transform lns Util.stdexcl

