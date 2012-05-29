import stdlib.web.client

/* functions exposed to clients */

module ServerLib {

    /* authentication */

    function read_login(f) {
        match (DropboxSession.get()) {
        case {~uid ...}: f({logged: Data.get_user_info(uid).display_name})
        default: f({unlogged})
        }
    }

    // Note:
    // server and exposed are basically equivalent in creating an entry point
    // server additionnally forbids the client to a version on his side
    @async exposed function push_login(){
        read_login(ViewLib.set_login(_));  //async push
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
    }

    /* navigation */

    function read_content(f) {
        ViewLib.content x = 
            match (DropboxSession.get()) {
            case {~current_path ...}: {folder: current_path}
            case {pending_request:_}: {error: <h2>An error occur during connection with Dropbox. Please sign in again or contact an administrator.</h2>}
            case {disconnected}: {welcome: <h2>Welcome to <b>StatBox</b>. Sign in with your <a href="http://www.dropbox.com">Dropbox</a> account to see your file statistics.</h2>}
            }
        f(x)
    } //FIXME: move the sentences somewhere else

    @async exposed function push_content(){
        read_content(ViewLib.set_content(_));
    }

    function read_data(path, f) {
        match (DropboxSession.get_uid()) {
        case {some:uid}:
            ViewLib.folder_info info =
                {counter: Analytics.count_folder_entries(uid, path)}
            f(info)
        default: void
        }
    }

    @async exposed function push_data(path){
        read_data(path, ViewLib.set_data(path, _));
    }

    @async exposed function move_to_path(string path) {
        match (DropboxSession.get()) {
        case {~uid, ~credentials, current_path:_}: DropboxSession.set({~uid, ~credentials, current_path: path})
        default: void
        }
        read_data(path, ViewLib.set_data(path, _)); // N.B. we don't user push... to ensure that get_data is computed before the last call
        push_content()
    }

}