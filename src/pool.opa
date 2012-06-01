
type Pool.msg('a) = { (string, (option('a) -> option('a))) replace }
//TODO: add set and get for more efficiency

type Pool.t('a) = Cell.cell(Pool.msg('a), option('a))

module Pool {

    private function pool_on_message(stringmap('a) map, Pool.msg('a) { replace: (key, f)}) {
        opt1 = StringMap.get(key, map);

        opt2 = f(opt1);
        
        match((opt1, opt2)) {
        case ({some:_}, {none}): 
            {return: opt2, instruction: {set: StringMap.remove(key, map)}}

        case ({some:val}, {some:val2}):
            if (val != val2) {
                {return: opt2, instruction: {set: StringMap.add(key, val2, map)}}
            } else {
                {return: opt2, instruction: {unchanged}}
            }

        case (_, {some:val2}):
            {return: opt2, instruction: {set: StringMap.add(key, val2, map)}}

        default:
            {return: opt2, instruction: {unchanged}}
        }
    }

    function make() {
        Pool.t('a) Cell.make(StringMap.empty, pool_on_message)
    }

    function set(pool, key, val) {
        ignore(Cell.call(pool, { replace : (key, function(_){some(val)})} ))
    }

    function get(pool, key) {
        Cell.call(pool, { replace : (key, function(x){x})} )
    }

    /* (useless)
    function get_with_default(pool, key, def) {
        Cell.call(pool, { replace : (key, function(x){
            match(x){
            case {none}: some(def)
            case _: x
            }})}) ? def
    }
*/

    function replace(pool, key, f) {
        Cell.call(pool, { replace : (key, f)} )
    }
}