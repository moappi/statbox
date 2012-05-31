import stdlib.web.client

/* functions exposed to clients */

// FIXME: make each of these function thread-safe by taking a 'mutex' on the uid

module ServerLib {

    /* authentication */

    function read_login() {
        match (DropboxSession.get()) {
        case {~uid ...}: {logged: Data.get_user_info(uid).display_name}
        default: {unlogged}
        }
    }

    @async exposed function push_login(){
        ViewLib.set_login(read_login());  //async push
    }

    @async exposed function sign_in() {
        match(DropboxSession.login_url()){
        case {success: url}:
            match(Uri.of_string(url)) {
            case {some:uri}: Client.go(uri)
            default:
                Log.error("sign_in", "wrong URI {url}")
                push_content();
                push_login()
            }
        default:
            push_content();
            push_login()
        }
    }

    @async exposed function log_out() {
        DropboxSession.set({disconnected});
        push_login()
        push_content();
    }

    /* navigation */

    function read_content() {
        match (DropboxSession.get()) {
        case {~current_path, ~uid, ~credentials}:
            if (Data.is_valid(current_path, uid)) {
                {folder: current_path, user_info:Data.get_user_info(uid).quota_info}
            } else {
                DropboxSession.set({current_path:Data.root_path, ~uid, ~credentials});
                {folder: Data.root_path, user_info:Data.get_user_info(uid).quota_info};
            }
        case {pending_request:_}: {error}
        case {disconnected}: {welcome}
        }
    }

    @async exposed function push_content(){
        ViewLib.set_content(read_content());
    }

    @async exposed function refresh_content(){
        match (DropboxSession.refresh_user_entries()) {
        case {success}:
            ViewLib.flush_data();
            push_content()
        default: Log.error("ServerLib.refresh_content", "failed")
        }
    }

    function read_data(path) {
        match (DropboxSession.get_uid()) {
        case {some:uid}:
            if (Data.is_valid(path, uid)) {
                ViewLib.folder_info info =
                    {counter: Analytics.count_folder_entries(uid, path),
                     total_size: Analytics.get_folder_total_size(uid, path),
                     dotslash_size: Analytics.get_folder_dotslash_size(uid, path),
                     full_path: Analytics.get_folder_full_path(uid, path),
                     subdirs: Analytics.list_folder_subdirs(uid, path),                 
                    }
                {some:info}
            } else {
                {none}
            }
        default: {none}
        }
    }

    @async exposed function push_data(path){
        match(read_data(path)) {
        case {some:data}: ViewLib.set_data(path, data)
        case {none}: void
        }
    }

    @async exposed function move_to_path(string path) {
        match (DropboxSession.get()) {
        case {~uid, ~credentials, current_path:_}: {
            if (Data.is_valid(path, uid)) {
                DropboxSession.set({~uid, ~credentials, current_path: path});
                match(read_data(path)) {
                case {some:data}: ViewLib.set_data(path, data)
                case {none}: void
                } // N.B. we don't use the async function push_data to ensure that get_data is computed before the last call
            } else {
                Log.error("ServerLib.move_to_path", "invalid path {path}");
            }
            push_content() // in any case
        }
        default: void
        }
    }

}