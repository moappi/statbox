
function error_page(html) {
    Resource.html("Error", <h1>{html}</h1>);
}

function go_to_dropbox_login_page() {
    match (DropboxSession.login_url()) {
    case {success: url}: Resource.default_redirection_page(url)
    case {~error}: error_page(error)
    }
}

function process_dropbox_token(string raw_token, string url) {
    match (DropboxSession.get_access(raw_token)) {
    case {~error}: error_page(error)
    case {success}: Resource.default_redirection_page(url)
    }
}

function main_page() {
    match (DropboxSession.get_uid()) {
    case {some: uid}:
        dbset(Data.entry, _) entries = /entries/all[uid == uid];
        info = /users/all[{~uid}]/last_info
        html = <div>
            <h2>Account informations</h2>
            {OpaSerialize.to_string(info)}
            <h2>Entries ({Analytics.count_user_entries(uid)})</h2>
            {Iter.to_list(Iter.map(entry_html, DbSet.iterator(entries)))}
        </div>;
        Resource.html("Welcome {info.display_name}", html);
    case {none}: go_to_dropbox_login_page()
    }
}

function user_html(Data.user u) {
    <div>{OpaSerialize.to_string(u)}</div>
}

function entry_html(Data.entry e) {
    <div>{OpaSerialize.to_string(e)}</div>
}

function admin_page() {
    dbset(Data.user, _) dbusers = /users/all;
    dbset(Data.entry, _) dbentries = /entries/all;
    users = <>{Iter.to_list(Iter.map(user_html, DbSet.iterator(dbusers)))}</>;
    entries = <>{Iter.to_list(Iter.map(entry_html, DbSet.iterator(dbentries)))}</>;
    html = <><h1>Users</h1>{users}<h1>Entries</h1>{entries}</>;
    Resource.html("Admin page", html);
}

dispatcher = parser {
case "/dropbox/connect?" raw_token=(.*) : process_dropbox_token(Text.to_string(raw_token), "/")
//case "/favicon.ico": **TODO**
case "/admin": admin_page()
case "/user" : main_page()
case "/" : Resource.html("Statbox", View.html());
}

Server.start(Server.http, [
//    { resources: @static_resource_directory("resources") },
//    { register: {css : ["resources/container.css"] }},
    {custom : dispatcher}
])