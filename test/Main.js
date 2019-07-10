
var perfMap = {}


exports.addToPerf = function(key) {
    return function(value) {
        return function() {
            if(perfMap[key] === null || perfMap[key] === undefined) {
                perfMap[key] = {count : 1 , value : value};
            } else {
                var c = perfMap[key].count;
                var v  = (perfMap[key].value * (c/(c+1))) + (value/(c+1)); 
                perfMap[key].count = c+1;
                perfMap[key].value = v;
            }
        }
    }
}

exports.printPerf = function() {
    console.log(perfMap);
    return {}
}