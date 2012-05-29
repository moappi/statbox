import custom.stdlib.apis.dropbox
import custom.stdlib.apis.oauth
import stdlib.core.rpc.core

type DropboxSession.status = 
   {disconnected}
or {OAuth.token pending_request}
or {Dropbox.credentials credentials, int uid, string current_path} //authenticated

protected UserContext.t(DropboxSession.status) context = UserContext.make({disconnected})

// Mathieu: TODO: deal with expiration of credentials via error codes
module DropboxSession {

    private D = Dropbox(dropbox_config)   // nobody should call Dropbox REST APIs outside this module

    function get() { UserContext.execute(function(s){ s }, context) }

    function set(r) { UserContext.change(function(_){ r }, context) }

    function get_uid() { 
        match(get()) {
        case {~uid ...}: some(uid)
        default: none
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
            set({~credentials, uid:info.uid, current_path:Data.root_path});
            process_delta_entries(info.uid, credentials, 0)
        default: // BUG of the API client: we don't fail on error codes != 200
            set({disconnected});
            mkerror("Error while retrieving the account information");
        }
    }

    private function process_delta_entries(int uid, Dropbox.credentials credentials, int counter) {
        match (D.Files.delta(Data.get_user_delta_options(uid), credentials)) {
        case {success:delta}:
            Data.update_user_entries(uid, delta);
            Data.set_user_delta_options(uid, delta.cursor);
            counter = counter + List.length(delta.entries);
            if (delta.has_more) {
                process_delta_entries(uid, credentials, counter)
            } else {
                Log.info("process_delta_entries", "processed {counter} entries in total");
                {success}
            }
        default: mkerror("Error while retrieving the deltas on files");
        }
    }
    
    function refresh_user_entries() {
        match (get()) {
        case {~credentials, ~uid, current_path:_}: process_delta_entries(uid, credentials, 0)
        default: mkerror("User not authenticated");
        }
    }
}
