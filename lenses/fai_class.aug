module FAI_Class = 

autoload xfm

let class = [ Sep.opt_space . key /[A-Z0-9_]+/ . Util.eol ]
let lns = (class|Util.empty)*

let xfm = transform lns Util.stdexcl

