import stdlib.themes.bootstrap
import stdlib.widgets.bootstrap

//import stdlib.tools.gcharts
import stdlib.apis.mongo
import stdlib.database.mongo

import custom.stdlib.apis.dropbox
import custom.stdlib.apis.oauth
import stdlib.core.rpc.core

WB = WBootstrap

host = "takehome2.dropbox.com"

// FIXME move keys away from the code
dropbox_config = {
    app_key: "6f8l9xg85hxiilr",
    app_secret: "xhw9qkcqdzzvfuk"
}

// FIXME share url definition with dispatcher below
dropbox_redirect_url = "http://{host}/dropbox/connect"

/* --- */
/* Credits: the following modules are based on MLstate's code examples by Cédric Soulas and Adam Koprowski */

D = Dropbox(dropbox_config)

type dropbox_status = 
   {disconnected}
or {OAuth.token pending_request}
or {Dropbox.credentials authenticated}

// Mathieu: TODO: save in DB and deal with expiration via error codes
module DropboxContext {

    UserContext.t(dropbox_status) context = UserContext.make({disconnected})

    function get() { UserContext.execute(function(s){ s }, context) }

    function set(r) { UserContext.change(function(_){ r }, context) }

}

DC = DropboxContext

module DropboxAuth {

    function mkerror(v) { {error: v} }

    function login_url() {
	match (D.OAuth.get_request_token(dropbox_redirect_url)) {
        case {success: s}:
            DC.set({pending_request: s});
	    {success: D.OAuth.build_authorize_url(s.token, dropbox_redirect_url) }
        case {~error}: mkerror("Error getting request token: {error}")
        }
    }

    function get_access(raw_token) { pass1(raw_token) }

    function pass1(raw_token) {
	match(DC.get()) {
	case {pending_request: req}: pass2(req, raw_token);
        case  _ : mkerror("The current user did not request a token")
        }
    }

    function pass2(req, raw_token) {
	match(D.OAuth.connection_result(raw_token)) {
	case {success: token}: pass3(req, token)
	case {~error}: mkerror("The providing arguments are invalid: {error}")
        }
    }

    function pass3(OAuth.token req, OAuth.token s) {
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

    function pass4(token, secret) {
	match (D.OAuth.get_access_token(token, secret, "")) {
        case {success: s}:
            Log.info("Oauth completed", "{OpaSerialize.to_string(s)}");
            DC.set({authenticated: {token:s.token, secret:s.secret}}); {success}
	case {~error}: mkerror("Impossible to retrieve an access token: {error}")
        }
    }
}

DA = DropboxAuth

function error_page(error) {
    Resource.html("Error", <h1>{error}</h1>)
}

function go_to_dropbox_login_page() {
    match (DA.login_url()) {
    case {success: url}: Resource.default_redirection_page(url)
    case {~error}: error_page(error)
    }
}

function process_dropbox_token(string raw_token, string url) {
    match (DA.get_access(raw_token)) {
    case {~error}: error_page(error)
    case {success}: Resource.default_redirection_page(url)
    }
}

function process_delta_entries(int uid, Dropbox.credentials credentials) {
    match (D.Files.delta(get_user_delta_options(uid), credentials)) {
    case {success:delta}:
        update_user_entries(uid, delta);
        set_user_delta_options(uid, delta.cursor);
        if (delta.has_more) process_delta_entries(uid, credentials)
        else true
    default: false
    }
}

function main_page_authenticated(Dropbox.credentials credentials) {
    match (D.Account.info(credentials)) {
    case {success:info}:
        update_user_info(info);
        if (process_delta_entries(info.uid, credentials)) {
            dbset(entry, _) entries = /entries/all[uid == info.uid];
            html = <div>
                <h2>Account informations</h2>
                {OpaSerialize.to_string(info)}
                <h2>Entries ({count_user_entries(info.uid)})</h2>
                {Iter.to_list(Iter.map(entry_html, DbSet.iterator(entries)))}
            </div>;
            Resource.html("Welcome {info.display_name}", html);
        } else {
            error_page("Error while retrieving the deltas on files");
        }
    default: // BUG of the API client: we don't fail on error codes != 200
        error_page("Error while retrieving the account information");
    }
}

function main_page() {
    match(DC.get()) {
    case {disconnected}: go_to_dropbox_login_page()
    case {pending_request: _}: Resource.html("Pending request", <h1>Pending request</h1>)
    case {authenticated: credentials}: main_page_authenticated(credentials)
    }
}

function user_html(user u) {
    <div>{OpaSerialize.to_string(u)}</div>
}

function entry_html(entry e) {
    <div>{OpaSerialize.to_string(e)}</div>
}

function admin_page() {
    dbset(user, _) dbusers = /users/all;
    dbset(entry, _) dbentries = /entries/all;
    users = <>{Iter.to_list(Iter.map(user_html, DbSet.iterator(dbusers)))}</>;
    entries = <>{Iter.to_list(Iter.map(entry_html, DbSet.iterator(dbentries)))}</>;
    html = <><h1>Users</h1>{users}<h1>Entries</h1>{entries}</>;
    Resource.html("Admin page", html);
}

dispatcher = parser {
case "/dropbox/connect?" raw_token=(.*) : process_dropbox_token(Text.to_string(raw_token), "/")
//case "/favicon.ico": **TODO**
case "/admin": admin_page()
case "/" : main_page()
}

Server.start(Server.http, [
//    { resources: @static_resource_directory("resources") },
//    { register: {css : ["resources/container.css"] }},
    {custom : dispatcher}
])