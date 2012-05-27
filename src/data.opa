
/* --- */

type user = {
    int uid,
    Dropbox.info last_info,
    string last_cursor // cursor for the delta function, "" means none
}

database users @mongo {
    user /all[{uid}]
}

type entry = {
    int uid,
    string path,
    Dropbox.metadata data 
}

database entries @mongo {
    entry /all[{uid, path}]
    /all[_]/data/is_deleted = {false}
    /all[_]/data/thumb_exists = {false}
}
//TODO: instruct Opa/MongoDB to build (secondary) indexes wrt. uid and path

/* --- */

function update_user_info(Dropbox.info info) { 
    /users/all[uid == info.uid] = {uid: info.uid, last_info: info, last_cursor: ""};
}

/*
function update_user_entries(int uid, ) { 
    /users/all[uid == info.uid] = {uid: info.uid, last_info: info, last_cursor: ""};
}
*/