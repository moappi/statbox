import stdlib.themes.bootstrap
import stdlib.widgets.bootstrap

//import stdlib.tools.gcharts
import stdlib.apis.mongo
import stdlib.database.mongo

import custom.stdlib.apis.dropbox
import stdlib.core.rpc.core

WB = WBootstrap

host = "takehome2.dropbox.com"

// FIXME move keys away from the code
dropbox_config = {
    app_key: "6f8l9xg85hxiilr",
    app_secret: "xhw9qkcqdzzvfuk"
}

dropbox_redirect = "http://{host}/dropbox/connect"

/* --- */
/* Credits: the following modules are based on MLstate's code examples by Cédric Soulas and Adam Koprowski */

D = Dropbox(dropbox_config)

type dropbox_status = 
   {disconnected}
or {Dropbox.creds pending_request}
or {Dropbox.creds authenticated}

// Mathieu: FIXME: OAuth should be stored in DB to survive server restart
// However Opa's OAuth client does not know how about HTTP error codes(!!), so it might be tricky to trigger a reauthentication when the tokens expire

module DropboxContext {

    UserContext.t(dropbox_status) context = UserContext.make({disconnected})

    function get() { UserContext.execute(function(s){ s }, context) }

    function set(r) { UserContext.change(function(_){ r }, context) }

}

DC = DropboxContext

module DropboxAuth {

    function err(v) { {error: v} }

    function login_url() {
	match (D.OAuth.get_request_token(dropbox_redirect)) {
        case {success: s}:
            DC.set({pending_request: {secret : s.secret, token:s.token}});
	    {success: D.OAuth.build_authorize_url(s.token, dropbox_redirect) }
        case {~error}: err("Error getting request token: {error}")
        }
    }

    function get_access(raw_token) { pass1(raw_token) }

    function pass1(raw_token) {
	match(DC.get()) {
	case {pending_request: creds}: pass2(creds, raw_token);
        case  _ : err("The current user did not request a token")
        }
    }

    function pass2(creds, raw_token) {
	match(D.OAuth.connection_result(raw_token)) {
	case {success: s}: pass3(creds, s)
	case {~error}: err("The providing arguments are invalid: {error}")
        }
    }

    function pass3(creds, s) {
	if (s.token == creds.token) {
	    if (s.verifier == "" && s.secret == "") {
	        pass4(s.token, creds.secret)
            } else {
		err("The connection result contains those unexpected values: verifier: '{s.verifier}' and secret: '{s.secret}'")
            }
        } else {
            err("The request token of the current user doesn't match provided arguments.")
        }
    }

    function pass4(token, secret) {
	match (D.OAuth.get_access_token(token, secret, "")) {
        case {success: s}:
            Log.info("Oauth completed", "{OpaSerialize.to_string(s)}");
            DC.set({authenticated: {token:s.token, secret:s.secret}}); {success}
	case {~error}: err("Impossible to retrieve an access token: {error}")
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

function process_dropbox_token(raw_token, url) {
    match (DA.get_access(raw_token)) {
    case {~error}: error_page(error)
    case {success}: Resource.default_redirection_page(url)
    }
}

function main_page_authenticated(creds) {
    match (D.Account.info(creds)) {
    case {success:info}:
        html = <div>{OpaSerialize.to_string(info)}</div>;
            /users/all[uid == info.uid] = {uid: info.uid, last_info: info, last_cursor: ""};
        Resource.html("Welcome {info.display_name}", html)
    default: // BUG of OPA stdlib: we never catch bugs here
        error_page("Error while retrieving the account information");
    }
}

function main_page() {
    match(DC.get()) {
    case {disconnected}: go_to_dropbox_login_page()
    case {pending_request: _}: Resource.html("Pending request", <h1>Pending request</h1>)
    case {authenticated: creds}: main_page_authenticated(creds)
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

Server.start(Server.http, {custom : dispatcher})