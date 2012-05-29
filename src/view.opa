import stdlib.themes.bootstrap
import stdlib.widgets.bootstrap

import stdlib.tools.gcharts

WB = WBootstrap
GC = GCharts

/* "Model" to be rendered by ViewLib */

type ViewLib.login = { string logged } or { unlogged }

type ViewLib.path = string // current folder path-key (lowercase, begins with "/" except for root_path="")

type ViewLib.user_info = Dropbox.quota_info

type ViewLib.content = { welcome } or { error } or { ViewLib.path folder, ViewLib.user_info user_info }

type ViewLib.data = map(ViewLib.path, ViewLib.folder_info)

type ViewLib.element = Dropbox.element

type ViewLib.path_element = { string label, string path_key }

type ViewLib.subdir_element = { string label, string path_key, option(int) total_size}

type ViewLib.folder_info = {
    int counter,
    option(int) total_size,
    list(ViewLib.path_element) full_path,
    list(ViewLib.subdir_element) subdirs    
}

// for some unknown reason, the Opa runtime fails if these reference are in the module below
    client reference(ViewLib.login) viewlib_login = ClientReference.create( {unlogged} )

    client reference(ViewLib.content) viewlib_content = ClientReference.create( {welcome} )

    client reference(ViewLib.data) viewlib_data = ClientReference.create(Map.empty)


module ViewLib {
    
    // server -> client synchro
    @async client function set_login(value) {
        ClientReference.set(viewlib_login, value)
        render_login();
    }

    @async client function set_content(value) {
        ClientReference.set(viewlib_content, value)
        render_content();
    }

    @async client function set_data(path, value) {
        ClientReference.set(viewlib_data, Map.add(path, value, ClientReference.get(viewlib_data)));

        match(ClientReference.get(viewlib_content)) {
        case {folder: path2 ...}: if (path == path2) render_content();
        default: void
        }
    }

    @async client function flush_data() {
        ClientReference.set(viewlib_data, Map.empty);
    }

    // rendering functions
    function render_login() {
        html =
            match(ClientReference.get(viewlib_login)){
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

// TODO prefetch data of subdirs?
    function render_folder(path, info) {
       #content =
        <div class=span9 id="main">
            <span class=span7>{path_html(path, info.full_path)}</span>
            <i class=icon-refresh onclick={function(_){ ServerLib.refresh_content()} }/>
            <span class=span2>{
                match(info.total_size){
                case {none}: "??"
                case {some:size}: human_readable_size(size)
                }
            } <span class="divider">/</span> {info.counter} elements</span>
        </div>

       <div class=span9>

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
        </div>
    }

    function path_html(path, full_path) {
        Log.info("path_html", "{path} {OpaSerialize.to_string(full_path)}");
        function label_html(~{label, path_key}) {
            hlabel =
                if (label == "") {
                  <img src="resources/dropbox_logo.png" alt="Root" height="48" width="48" />
                } else {
                  <h3>{label}</h3>
                }
            ha =  <a href="#" onclick={function(_){ServerLib.move_to_path(path_key)}}>{hlabel}</a>
                  <+> <span class="divider">/</span>
            if (path_key == path) { // last one?
                  <li class="active">{ha}</li>
            } else {
                  <li>{ha}</li>
            }
        }

        <ul class="breadcrumb">{List.map(label_html, full_path)}</ul>
    }


    function human_readable_size(int bytes) {
        if (bytes < 1024*1000) {
            "{bytes / 1024} Kb"
        } else if (bytes < 1024*1024*1000) {
            "{bytes / (1024*1024)} Mb"            
        } else {
            "{bytes / (1024*1024*1024)} Gb"            
        }
    }

    function human_readable_percentage(float x) { // FIXME ugly
        "{(Float.to_int(x*100.))}.{Float.to_int(10.*(100.*x - Float.floor(100.*x)))} %"
    }

    function render_user_info(Dropbox.quota_info {~shared, ~normal, ~total}) {
        s = Float.of_int(shared)
        n = Float.of_int(normal)
        t = Float.of_int(total)
        ratio_used = (s + n) / t
        ratio_shared = s / (s + n)

        // TODO: on-mouseover % => real size 
        // Or progress bar: <div class="progress"> <div class="bar" style="width: 60%;"></div></div>
        #footer = <p>You are using {human_readable_percentage(ratio_used)} of the {human_readable_size(total)} of available, {human_readable_percentage(ratio_shared)} of your files are shared. </p>
    }

    function default_footer_html() {
        <p>&copy; Mathieu Baudet 2012 -- CSS styles and layout by Twitter Bootstrap</p>
    }

    function welcome_html() {
        <div class="hero-unit">
        <h1>Welcome to {application_name}</h1>
        <p>Sign in with your <a href="http://www.dropbox.com">Dropbox</a> account to see your file statistics.</p>
        <p><a class="btn btn-primary btn-large" onclick={function(_){ServerLib.sign_in()}}>Sign in</a></p>
        </div>
    }

    function error_html() {
      <div class="alert alert-error">
        <h1>Oups</h1>
        <p>An error occur during the connection with Dropbox. Please sign in again.</p>
        <p><a class="btn btn-primary btn-large" onclick={function(_){ServerLib.sign_in()}}>Sign in</a></p>
      </div>
    }

    function render_content() {
        match(ClientReference.get(viewlib_content)) {
        case {folder: path, ~user_info}:
            m = ClientReference.get(viewlib_data)
            if (Map.mem(path, m) == false) {
                Log.info("ViewLib", "missing data for path {path}: requesting server");
                ServerLib.push_data(path)
            } else {
                match (Map.get(path, m)) {
                case {some: info}:
                    render_folder(path, info)
                    render_user_info(user_info)
                default: void
                }
            }
        case {welcome}:
            #content = welcome_html();
            #footer = default_footer_html()

        case {error}:
            #content = error_html()
            #footer = default_footer_html()

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
            {welcome_html()}
      </div>
      <hr>
      <footer class="footer" id="footer">
            {default_footer_html()}
      </footer>
    </div>
    }
}
