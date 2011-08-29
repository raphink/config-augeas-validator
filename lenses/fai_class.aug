module FAI_Class = 

let class = [ Sep.opt_space . key /[A-Z0-9_]+/ . Util.eol ]
let lns = (class|Util.empty)*

