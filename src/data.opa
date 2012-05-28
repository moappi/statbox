import stdlib.database.mongo

/* --- */

type user = {
    int uid,
    Dropbox.info last_info,
    option(string) last_cursor // cursor for the delta function
}

database users @mongo {
    user /all[{uid}]
}

type entry = {
    int uid,
    string path,
    Dropbox.element element
}

database entries @mongo {
    entry /all[{uid, path}]

    //default values
    /all[_]/element/kind = { file: { mime_type: "", client_mtime: {none}} }
    /all[_]/element/kind/folder/contents = { none }
    /all[_]/element/metadata/is_deleted = {false}
    /all[_]/element/metadata/thumb_exists = {false}
}

//moreover instruct MongoDB to build an index wrt. uid alone
// FIXME: broken?
// DbSet.index(@/entries, ["all", "uid"])

/* --- */

// TODO: ensure atomicity of the DB to deal with concurrent accesses by the same user

function update_user_info(Dropbox.info info) { 
        /users/all[{uid: info.uid}]/last_info = info
}

function get_user_delta_options(int uid) {
    (Dropbox.delta_options) {cursor: /users/all[{~uid}]/last_cursor}
}

function set_user_delta_options(int uid, string cursor) {
    /users/all[{~uid}]/last_cursor = some(cursor)
}

function flush_user_entries(int uid) {
    dbset(entry, _) entries = /entries/all[uid == uid];
    Iter.iter(
        function(e) { Db.remove(@/entries/all[{uid:e.uid, path:e.path}]) },
        DbSet.iterator(entries)
    )
}

function count_user_entries(int uid) {
    dbset(entry, _) entries = /entries/all[uid == uid];
    Iter.count(
        DbSet.iterator(entries)
    )
}

function process_delta_entry(int uid, Dropbox.delta_entry e) {
    path = e.path
    dbpath = @/entries/all[{~uid, ~path}]
    match(e.metadata) {
    case {some: element}:
        if (element.metadata.path == "") Db.remove(dbpath) // work around supposedly a bug of the API
        else Db.write(dbpath, {~uid, ~path, ~element})
    case default: Db.remove(dbpath)
    }
}

function update_user_entries(int uid, Dropbox.delta delta) { 
    if (delta.reset) {
        flush_user_entries(uid)
    } else {
        List.iter(process_delta_entry(uid, _), delta.entries)
    }
}
