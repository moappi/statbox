import custom.stdlib.apis.dropbox
import custom.stdlib.apis.oauth
import stdlib.core.rpc.core

type DropboxSession.status = 
   {disconnected}
or {OAuth.token pending_request}
or {Dropbox.credentials credentials, int uid, string current_path, bool refreshing, option(ViewActor.chan) view_actor} //authenticated

// FIXME: memory leak (we never clean the cookie table) 
protected Pool.t(DropboxSession.status) context = Pool.make()

// Mathieu: TODO: deal with expiration of credentials via error codes
module DropboxSession {

    private D = Dropbox(dropbox_config)   // nobody should call Dropbox REST APIs outside this module

    private init_state = {disconnected}

    function get() { (Pool.get(context, HttpRequest.get_cookie()?"") ? init_state) }

    function set(r) { Pool.set(context, HttpRequest.get_cookie()?"", r) }

    function get_by_cookie(key) { (Pool.get(context, key?"") ? init_state) }

    function set_by_cookie(key, r) { Pool.set(context, key?"", r) }

    function get_uid() { 
        match(get()) {
        case {~uid ...}: some(uid)
        default: none
        }
    }

    function get_view_actor() { 
        match(get()) {
        case {~view_actor ...}: view_actor
        default: none
        }
    }

    function set_view_actor(view_actor) { 
        match (get()) {
        case {~uid, ~credentials, ~current_path, ~refreshing, view_actor:_}:
            set({~uid, ~credentials, ~current_path, ~refreshing, ~view_actor})
        default:
            Log.info("DropboxSession.set_view_Actor", "discarding actor")
        }
    }

    function set_refresh_by_cookie(cookie, flag) { 
        match (get_by_cookie(cookie)) {
        case {~uid, ~credentials, ~current_path, refreshing:_, ~view_actor}:
            set_by_cookie(cookie, {~uid, ~credentials, ~current_path, refreshing:flag, ~view_actor})
        default: void
        }
    }

    /* Credits: the following modules are based on a code sample by Cédric Soulas */

    private function mkerror(v) { {error: v} }

    /* start OAuth connexion with Dropbox and retrieve the URL to Dropbox login page */
    function login_url() {
	match (D.OAuth.get_request_token(dropbox_redirect_url)) {
        case {success: s}:
            set({pending_request: s});
	    {success: D.OAuth.build_authorize_url(s.token, dropbox_redirect_url) }
        case {~error}: mkerror("Error getting request token: {error}")
        }
    }

    /* complete connexion with Dropbox and retrieve the user data */
    function get_access(string raw_token) {
        pass1(raw_token)
    }

    private function pass1(raw_token) {
	match(get()) {
	case {pending_request: req}: pass2(req, raw_token);
        case  _ : mkerror("The current user did not request a token")
        }
    }

    private function pass2(req, raw_token) {
	match(D.OAuth.connection_result(raw_token)) {
	case {success: token}: pass3(req, token)
	case {~error}: mkerror("The providing arguments are invalid: {error}")
        }
    }

    private function pass3(OAuth.token req, OAuth.token s) {
	if (s.token == req.token) {
	    if (s.verifier == "" && s.secret == "") {
	        pass4(s.token, req.secret)
            } else {
		mkerror("The connection result contains those unexpected values: verifier: '{s.verifier}' and secret: '{s.secret}'")
            }
        } else {
            mkerror("The request token of the current user doesn't match provided arguments.")
        }
    }

    private function pass4(token, secret) {
	match (D.OAuth.get_access_token(token, secret, "")) {
        case {success: s}:
            Log.info("Oauth completed", "{OpaSerialize.to_string(s)}");
            pass5({token:s.token, secret:s.secret});
	case {~error}: mkerror("Impossible to retrieve an access token: {error}")
        }
    }

    private function pass5(Dropbox.credentials credentials) { 
        match (D.Account.info(credentials)) {
        case {success:info}:
            Data.update_user_info(info);
            set({~credentials, uid:info.uid, current_path:Data.root_path, refreshing:true, view_actor:get_view_actor()});
            Scheduler.push(function(){ignore(refresh_user_entries(function(){void}, false))});
            {success}
        default: // BUG of the API client: we don't fail on error codes != 200
            set({disconnected});
            mkerror("Error while retrieving the account information");
        }
    }

    private function process_delta_entries(int uid, Dropbox.credentials credentials, int counter, (-> void) callback) {
        match (D.Files.delta(Data.get_user_delta_options(uid), credentials)) {
        case {success:delta}:
            Data.update_user_entries(uid, delta);
            Data.set_user_delta_options(uid, delta.cursor);
            counter = counter + List.length(delta.entries);
            if (delta.has_more) {
                process_delta_entries(uid, credentials, counter, callback)
            } else {
                Log.info("process_delta_entries", "processed {counter} entries in total");
                
                daemon = SizeDaemons.get_mine(uid);
                Session.send(daemon, { ready : callback });
                {success}
            }
        default: mkerror("Error while retrieving the deltas on files");
        }
    }
    
    function refresh_user_entries(refresh_view, bool background_task) {
        match (get()) {
        case {~credentials, ~uid, ~current_path, refreshing:_, ~view_actor}:
            cookie = HttpRequest.get_cookie()
            function callback() {
                set_refresh_by_cookie(cookie, false);
                refresh_view()
            }
            set_refresh_by_cookie(cookie, true);
            if (background_task == false) refresh_view();
            process_delta_entries(uid, credentials, 0, callback)
        default: mkerror("User not authenticated");
        }
    }
}
