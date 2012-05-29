import stdlib.themes.bootstrap
import stdlib.widgets.bootstrap

import stdlib.tools.gcharts

WB = WBootstrap
GC = GCharts

type ViewLib.login = { string logged} or { unlogged }

type ViewLib.path = string // current folder path-key (lowercase, begins with "/")

type ViewLib.content = { xhtml welcome } or { xhtml error } or { ViewLib.path folder }

type ViewLib.data = map(ViewLib.path, ViewLib.folder_info)

type ViewLib.element = Dropbox.element

type ViewLib.folder_info = {
    int counter
//    list(string) full_path,
//    list(ViewLib.element) content,
    // ...
}

// for some unknown reason Opa runtime fails if these reference are in the module below
    client reference(ViewLib.login) login = ClientReference.create( {unlogged} )

    client reference(ViewLib.content) content = ClientReference.create( {welcome : <></>} )

    client reference(ViewLib.data) data = ClientReference.create(Map.empty)


module ViewLib {
    
    // server -> client synchro
    @async client function set_login(value) {
        ClientReference.set(login, value)
        render_login();
    }

    @async client function set_content(value) {
        ClientReference.set(content, value)
        render_content();
    }

    @async client function set_data(path, value) {
        ClientReference.set(data, Map.add(path, value, ClientReference.get(data)));

        match(ClientReference.get(content)) {
        case {folder: path2}: if (path == path2) render_content();
        default: void
        }
    }

    // rendering functions
    function render_login() {
        html =
            match(ClientReference.get(login)){
            case {unlogged}:
                WB.Button.make({button:<>Sign in</>, callback:function(_){ServerLib.sign_in()}}, [{primary}])
            case {logged: name}:
                WB.Navigation.nav([
                    {custom_li: WB.Navigation.dropdown_li(<>{name}</>, none, [
                        {inactive:<>Log out</>, href:some("#"), onclick:{function(_){ServerLib.log_out()}}}
                    ])}
                ], false)
            }
        #login = html
    }

    function render_content() {
        match(ClientReference.get(content)) {
        case {folder: path}:
            m = ClientReference.get(data)
            if (Map.mem(path, m) == false) {
                Log.info("ViewLib", "missing data for path {path}: requesting server");
                ServerLib.push_data(path)
            } else {
                match (Map.get(path, m)) {
                case {some: {counter: n}}: #content = <h2>Folder {path} has {n} files</h2>
                default: void
                }
            }
        case {welcome: html}: #content = html  //TODO: improve display
        case {error: html}: #content = html
        }
    }

    // server side construction of the initial main view
    function html() {
            <div id="view" onready={function(_){ServerLib.push_login(); ServerLib.push_content()}}>{
                WB.Navigation.navbar(
                    WB.Layout.fixed(
                        WB.Navigation.brand(<>StatBox</>, some("/"), ignore) <+>
                        WB.pull_right(<span id="login"/>)
                    )
                ) <+>
                WB.Layout.fixed(<div id="path"/><div id="content"/>)
            }</div>
    }
}
