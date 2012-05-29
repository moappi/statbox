import stdlib.themes.bootstrap
import stdlib.widgets.bootstrap

import stdlib.tools.gcharts

WB = WBootstrap
GC = GCharts

type ViewLib.login = { string logged} or { unlogged }

type ViewLib.path = string // current folder path-key (lowercase, begins with "/")

type ViewLib.content = { welcome } or { error } or { ViewLib.path folder }

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

    client reference(ViewLib.content) content = ClientReference.create( {welcome} )

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
                  <div class="pull-right">
                    <ul class="nav">
                    <li class="dropdown">
                    <a class="dropdown-toggle" data-toggle="dropdown">
                       {name}<b class="caret"></b>
                    </a>
                    <ul class="dropdown-menu">
                    <li><a href="#" onclick={function(_){ServerLib.log_out()}}>Log out</a></li>
                    </ul>
                    </li>
                    </ul>
                 </div>
            }
        #login = html
    }

    function render_folder(path, info) {
        <div class="span3" id="navigation">
          <div class="well sidebar-nav" id="navigation">
            <ul class="nav nav-list">
            <li class="nav-header">Sidebar</li>
            <li class="active"><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li class="nav-header">Sidebar</li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li class="nav-header">Sidebar</li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            <li><a href="#">Link</a></li>
            </ul>
          </div>
        </div>
        <div class=span9 id="main">
          <h2>Folder {path} has {info.counter} files</h2>
        </div>
    }

    function render_welcome() {
        <div class="hero-unit">
        <h1>Welcome to {application_name}</h1>
        <p>Sign in with your <a href="http://www.dropbox.com">Dropbox</a> account to see your file statistics.</p>
        <p><a class="btn btn-primary btn-large" onclick={function(_){ServerLib.sign_in()}}>Sign in</a></p>
        </div>
    }

    function render_error() {
        <h1>Oups</h1>
        <p>An error occur during the connection with Dropbox. Please sign in again.</p>
        <p><a class="btn btn-primary btn-large" onclick={function(_){ServerLib.sign_in()}}>Sign in</a></p>
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
                case {some: info}: #content = render_folder(path, info)
                default: void
                }
            }
        case {welcome}: #content = render_welcome()

        case {error}: #content = render_error()
        }
    }

    // server side construction of the initial main view
    function html() {
    <div class="navbar navbar-fixed-top" id="view" onready={function(_){ServerLib.push_login(); ServerLib.push_content()}}>
      <div class="navbar-inner">
        <div class="container-fluid">
          <a class="brand" href="#">{application_name}</a>
          <span id="login" class="pull-right"/>
        </div>
      </div>
    </div>
    <div class="container-fluid">
      <div class="row-fluid" id="content">
            {render_welcome()}
      </div>
      <hr>
      <footer>
            <p>&copy; Mathieu Baudet 2012 -- CSS styles and layout by Twitter Bootstrap</p>
      </footer>
    </div>
    }
}


Resource.register_external_js("http://twitter.github.com/bootstrap/assets/js/bootstrap-dropdown.js")
