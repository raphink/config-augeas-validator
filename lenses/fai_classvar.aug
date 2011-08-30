module FAI_ClassVar =

autoload xfm

let modprobe = [ Build.xchg "modprobe" "modprobe" "#modprobe"
               . Sep.space . store Rx.word . Util.eol ]

let lns = (Shellvars.comment | Shellvars.empty | Shellvars.source
         | Shellvars.kv | Shellvars.unset | Shellvars.bare_export
         | Shellvars.builtin | modprobe) *

let xfm = transform lns Util.stdexcl

