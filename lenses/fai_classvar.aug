module FAI_ClassVar =

autoload xfm

let modprobe = [ Build.xchg "modprobe" "modprobe" "#modprobe"
               . Sep.space . store Rx.word . Util.eol ]

let lns = Shellvars.lns | modprobe

let xfm = transform lns Util.stdexcl

