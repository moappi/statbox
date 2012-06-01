import stdlib.apis.mongo
import stdlib.database.mongo

/* --- */

type Data.user = {
    int uid,
    Dropbox.info last_info,
    option(string) last_cursor // cursor for the delta function
}

database users @mongo {
    Data.user /all[{uid}]
}

type Data.entry = {
    int uid,
    string path, // lowercased by dropbox
    option(string) parent, // computed path for the parent folder (lowercased)
    Dropbox.element element,
    option(int) total_size // none if not computed yet
// TODO    map(Data.icon, int) icon_size_map // computed as the same time as total_size
}

database entries @mongo {
    Data.entry /all[{uid, path}]

    //default values
    /all[_]/parent = {none}
    /all[_]/element/kind = { file: { mime_type: "", client_mtime: {none}} }
    /all[_]/element/kind/folder/contents = {none}
    /all[_]/element/metadata/is_deleted = {false}
    /all[_]/element/metadata/thumb_exists = {false}
}

//moreover instruct MongoDB to build an index wrt. uid alone and wrt. uid and parent
// FIXME: broken?
// DbSet.index(@/entries, ["all", "uid"])
// DbSet.indexes(@/entries, [["all", "uid"],["all", "parent"]])

/* --- */

// TODO: check & ensure atomicity of the DB to deal with concurrent accesses by the same user + make sure the same credentials and cursor are used for Dropbox

module Data {

root_path = ""

function update_user_info(Dropbox.info info) { 
        /users/all[{uid: info.uid}]/last_info = info
}

function get_user_info(int uid) { 
        /users/all[{~uid}]/last_info
}


function get_user_delta_options(int uid) {
    (Dropbox.delta_options) {cursor: /users/all[{~uid}]/last_cursor}
}

function set_user_delta_options(int uid, string cursor) {
    /users/all[{~uid}]/last_cursor = some(cursor)
}

function flush_user_entries(int uid) { // FIXME slow
    dbset(Data.entry, _) entries = /entries/all[uid == uid];
    Iter.iter(
        function(e) { Db.remove(@/entries/all[{uid:e.uid, path:e.path}]) },
        DbSet.iterator(entries)
    )
}

function schedule_size_computation(int uid, string pathkey) {
    daemon = SizeDaemons.get_mine(uid);
    Session.send(daemon, {schedule_path: pathkey})
}

function is_folder(Dropbox.element element) {
    match(element) {
    case {kind:{folder:_} ...}: true
    case {kind:{file:_} ...}: false
    }
}

    function is_valid(string path, int uid) {
    (path == root_path) || (?/entries/all[{~path, ~uid}] != {none})
}

function process_delta_entry(int uid, Dropbox.delta_entry de) {
//    Log.info("Data.process_delta_entry", "Processing delta entry: {de.path}");
    path = de.path
    dbpath = @/entries/all[{~uid, ~path}]
    match(de.metadata) {
    case {some: element}:
        //Log.info("Data.process_delta_entry", "Writing entry {uid}:{de.path} = {OpaSerialize.to_string({~uid, ~path, ~element})}");
        parent = PathTool.compute_parent(path);
        size =
            if (is_folder(element)) {
                schedule_size_computation(uid, path);
                {none}
            } else { // sizes of files are known
                match(parent) {
                case {some:p}: schedule_size_computation(uid, p);
                default: void
                };
                {some: element.metadata.bytes}
            };
        new_element = {~uid, ~path, ~element, ~parent, total_size:size};
        Db.write(dbpath, new_element)
    case default:
        match(PathTool.compute_parent(path)) {
        case {none}: void
        case {some: parent}: schedule_size_computation(uid, parent)
        };
        //Log.info("Data.process_delta_entry", "Removing entry {uid}:{de.path}");
        Db.remove(dbpath)
    }
}

function update_user_entries(int uid, Dropbox.delta delta) {
    daemon = SizeDaemons.get_mine(uid);

    recursive function f() {
        if (delta.reset) {
            Log.info("Data.update_user_entries", "Flushing all data of user {uid}");
            flush_user_entries(uid);
            Log.info("Data.update_user_entries", "Flushing data done");
        }
        
        Log.info("Data.update_user_entries", "Processing delta entries for user {uid}");
        List.iter(process_delta_entry(uid, _), delta.entries);
        Log.info("Data.update_user_entries", "Processing delta entries done");
        
        // don't launch the daemon too early
        if (delta.has_more == false) {
            Log.info("Data.update_user_entries", "Requesting the computation of sizes of folders");
            Session.send(daemon, { go });
        }
    }

    Session.send(daemon, { ready: f });
}

}

type SD.msg = { string schedule_path } or { go } or { (-> void) ready }

type SD.daemon = Session.channel(SD.msg)

// TODO: memory leak: we never kill daemons
module SizeDaemons {
    
    private function update_size(int uid, stringset todo_set, string path) {
        function f(size, entry) {
            if (Data.is_folder(entry.element))
                size + update_size(uid, todo_set, entry.path)
            else
                size + entry.element.metadata.bytes
        }

        if (StringSet.mem(path, todo_set) || (/entries/all[{~uid, ~path}]/total_size == {none})) {
            //TODO: filter out regular files with Mongo
            dbset(Data.entry, _) entries =
                /entries/all[uid == uid and parent == {some:path}];

            size = DbSet.fold(0, entries)(f);

            /entries/all[{~uid, ~path}]/total_size = {some: size};

            size
        } else {
            (/entries/all[{~uid, ~path}]/total_size ? {Log.error("SizeDaemons.update_size", "encountered invalid zero size"); 0})
        }
    }
    
    private function make_daemon(int uid) {
        function on_message(list(string) state, SD.msg mess) {
            match (mess) {
            case {schedule_path: path}: {set: List.cons(path, state)}
            case {ready: f}:
                f();
                {unchanged}
            case {go}:
                Log.info("SizeDaemons", "Starting computation of sizes of folders");
                todo_set = List.fold(function (path, set) {
                    PathTool.fold_parents(function (p, s){ StringSet.add(p, s) }, path, set)
                }, state, StringSet.empty);
                _ = update_size(uid, todo_set, Data.root_path);
                Log.info("SizeDaemons", "Terminated computation of sizes of folders (for now)");
                {set : []}
            }
        }

        Session.make(list(string) [], on_message)
    }

    private function pool_on_message(intmap(SD.daemon) map, int uid) {
        match (IntMap.get(uid, map)) {
        case {none}:
            d = make_daemon(uid)
            map2 = IntMap.add(uid, d, map)
            {return: d, instruction: {set: map2}}
        case {some: d}:
            {return: d, instruction: {unchanged}}
        }
    }

    private Cell.cell(int, SD.daemon) pool = Cell.make(intmap(SD.daemon) IntMap.empty, pool_on_message)

    function get_mine(int uid) {
        Cell.call(pool, uid)
    }
}

module Analytics { // TODO: cache everything in server RAM (with limit)
    
function count_user_entries(int uid) { // FIXME slow
    dbset(Data.entry, _) entries = /entries/all[uid == uid];
    Iter.count(
        DbSet.iterator(entries)
    )
}

function fold_user_entries(int uid, init, f) {
    dbset(Data.entry, _) entries = /entries/all[uid == uid];
    DbSet.fold(init, entries)(f)
}

function count_folder_entries(int uid, string folder) {
    dbset(Data.entry, _) entries = /entries/all[uid == uid and parent == {some:folder}];
    Iter.count(
        DbSet.iterator(entries)
    )
}

function fold_folder_entries(int uid, string folder, init, f) {
    dbset(Data.entry, _) entries = /entries/all[uid == uid and parent == {some:folder}];
    DbSet.fold(init, entries)(f)
}

function get_folder_total_size(uid, path) {
    (?/entries/all[{~uid, ~path}]/total_size ? {none})
}

function get_folder_dotslash_size(uid, path) {

    function f(size, entry) {
        if (Data.is_folder(entry.element)) size
        else size + entry.element.metadata.bytes
    }

    // TODO filter out folders within Mongo
    dbset(Data.entry, _) entries =
        /entries/all[uid == uid and parent == {some:path}];

    DbSet.fold(0, entries)(f);
}

function get_folder_full_path(uid, path) {
    function f(path, acc) {
        label = PathTool.compute_filename(/entries/all[{~uid, ~path}]/element/metadata/path)
        List.cons({label:label, path_key:path}, acc)
    }
    PathTool.fold_parents(f, path, [])
}
     
function list_folder_subdirs(uid, path) {
    function f(l, e) {
        if (Data.is_folder(e.element)) {
            ViewLib.subdir_element el = {
                label:PathTool.compute_filename(e.element.metadata.path),
                path_key:e.path,
                total_size:e.total_size
            }
            List.cons(el, l)
        } else l
    }
    dbset(Data.entry, _) entries = /entries/all[uid == uid and parent == {some:path}];
    //TODO: filter out regular files with Mongo

    DbSet.fold([], entries)(f)    
}

}

//FIXME: these functions assume some normalization like "foo//bar/" -> "/foo/bar"
//Otherwise a path ending with "/foo/" will be cut into ["", foo, ""] 
module PathTool {

function find_slash_backward(int n, string path) { // n must be < String.length(path)
    if (n < 0) n
    else if (String.get(n, path) == "/")
        n
    else {
        find_slash_backward(n-1, path)
    }
}

function compute_parent(string path) {
    n = String.length(path)
    i = find_slash_backward(n-1, path);
    res = if (i < 0) {
        {none}
    } else {
        String.get_prefix(i, path) // drop the "/" seen as well
    }
//    Log.info("PathTool.compute_parent", "'{path}' ==> '{res}'");
    res
}

function compute_filename(string path) {
    n = String.length(path)
    i = find_slash_backward(n-1, path);
    res = if (i < 0)
        path
    else
        String.sub(i+1, n-1-i, path) // drop the "/" found
//    Log.info("PathTool.compute_filename", "'{path}' ==> '{res}'");
    res
}

function fold_parents(f, path, map) {
    map2 = f(path, map)
    match(compute_parent(path)) {
    case {none}: map2
    case {some: path2}: fold_parents(f, path2, map2)
    }
}

}