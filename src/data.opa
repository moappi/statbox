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
    Dropbox.element element
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

// TODO: ensure atomicity of the DB to deal with concurrent accesses by the same user

module Data {

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

function find_slash_backward(int n, string path) {
    if (n < 0) n
    else if (String.get(n, path) == "/")
        n
    else {
        find_slash_backward(n-1, path)
    }
}

function compute_parent(string path) {
    i =  find_slash_backward(String.length(path)-1, path);
    if (i < 0) {
        Log.error("Data.compute_parent", "Path contains no slash");
        {none}
    } else {
        String.get_prefix(i+1, path)
    }
}

function process_delta_entry(int uid, Dropbox.delta_entry e) {
    Log.info("Data.process_delta_entry", "Processing delta entry: {e.path}");
    path = e.path
    dbpath = @/entries/all[{~uid, ~path}]
    match(e.metadata) {
    case {some: element}:
        Log.info("Data.process_delta_entry", "Writing entry {uid}:{e.path} = {OpaSerialize.to_string({~uid, ~path, ~element})}");
        Db.write(dbpath, {~uid, ~path, ~element, parent:compute_parent(path)})
    case default: Db.remove(dbpath)
        Log.info("Data.process_delta_entry", "Removing entry {uid}:{e.path}");
    }
}

function update_user_entries(int uid, Dropbox.delta delta) { 
    if (delta.reset) {
        Log.info("Data.update_user_entries", "Flushing all data of user {uid}");
        flush_user_entries(uid);
        Log.info("Data.update_user_entries", "Flushing data done");
    }
    Log.info("Data.update_user_entries", "Processing delta entries for user {uid}");
    List.iter(process_delta_entry(uid, _), delta.entries);
    Log.info("Data.update_user_entries", "Processing delta entries Done");
}

}

module Analytics { // FIXME cache everything in server RAM (with limit)
    
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

function count_folder_entries(int uid, string folder) { // FIXME slow
    dbset(Data.entry, _) entries = /entries/all[uid == uid and parent == {some:folder}];
    Iter.count(
        DbSet.iterator(entries)
    )
}

function fold_folder_entries(int uid, string folder, init, f) {
    dbset(Data.entry, _) entries = /entries/all[uid == uid and parent == {some:folder}];
    DbSet.fold(init, entries)(f)
}

}