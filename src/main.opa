
/* --- (read-only) admin page for debug --- */

//TODO: move the 'secret' admin string below to 'config.opa'

function user_html(Data.user u) {
    <tr><td>{OpaSerialize.to_string(u)}</td></tr>
}

function entry_html(Data.entry e) {
    <tr><td>{OpaSerialize.to_string(e)}</td></tr>
}

function admin_page() {
    dbset(Data.user, _) dbusers = /users/all;
    dbset(Data.entry, _) dbentries = /entries/all;
    users = <table class="table table-striped">{Iter.to_list(Iter.map(user_html, DbSet.iterator(dbusers)))}</table>;
    entries = <table class="table table-striped">{Iter.to_list(Iter.map(entry_html, DbSet.iterator(dbentries)))}</table>;
    html = <h1>Users</h1> <+> users <+> <h1>Entries</h1> <+> entries;
    Resource.html("Statbox admin page", html);
}

/* --- URL dispatcher --- */

function process_dropbox_token(string raw_token, string url) {
    _ = DropboxSession.get_access(raw_token);
    Resource.default_redirection_page(url);
    // N.B. The default page will display the error message if necessary
}

dispatcher = parser {
case "/dropbox/connect?" raw_token=(.*):
    process_dropbox_token(Text.to_string(raw_token), "/")
case "/admin13zxx5769": admin_page()
case "/" :
    content = ServerLib.read_content();
    login = ServerLib.read_login();
    pathdata = match (content) {
    case {folder: path ...}: ServerLib.read_data(path)
    default: {none}
    }
    Log.info("URL dispatcher", "Server page / with params {(content, login, pathdata)}");
    Resource.html("{application_name}", ViewMake.page_html(login, content, pathdata));
}

Server.start(Server.http, [
    { resources: @static_resource_directory("resources") },
    { register: {css : ["resources/statbox.css"] }},
    { custom : dispatcher }
])

// required for dropdown menus
Resource.register_external_js("http://twitter.github.com/bootstrap/assets/js/bootstrap-dropdown.js")

// required for Gcharts
Resource.register_external_js("https://www.google.com/jsapi")

// add the favicon link to the http header
Resource.register_external_favicon(Favicon.make({ico}, "resources/favicon.ico"))
