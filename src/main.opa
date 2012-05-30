
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
    Resource.default_redirection_page(url)
}

dispatcher = parser {
case "/dropbox/connect?" raw_token=(.*) : process_dropbox_token(Text.to_string(raw_token), "/")
//case "/favicon.ico": **TODO**
case "/admin13zxx5769": admin_page()
case "/" : Resource.html("{application_name}", ViewLib.html());
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
