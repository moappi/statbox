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
    int dotslash_size,
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

    function size_opt_html(sizeopt) {
        match(sizeopt){
        case {none}: <p>??</p>
        case {some:size}: human_readable_size(size)
        }
    }

    function subdir_html({~label, ~path_key, ~total_size}, int limit) {
            <span><a href="#" onclick={function(_){ServerLib.move_to_path(path_key)}}>{string_limit(label, limit)}</a> {size_opt_html(total_size)}</span>
    }

// TODO prefetch data of subdirs?
    function render_folder(string path, ViewLib.folder_info info) {
      /* navigation */
      #content =
        <div class="row" id="pathnav">
          <div class="span6 offset3">{path_html(path, info.full_path)}</div>
          <div class="span1">
            <a onclick={function(_){ ServerLib.refresh_content()} }>
              <img src="resources/refresh.png" alt="refresh" height="32" width="32" />
            </a>
          </div>
          <div class="span2">
            { size_opt_html(info.total_size) }
            <span class="divider">/</span>
            {info.counter} elements
          </div>
        </div>

       <div class="row">
          <div class="well span3" id="navigation">
            <div class="sidebar-nav" id="navigation">
              <ul class="nav nav-list">
              <li class="nav-header">{"{path}"}</li>
              {List.map(function(sd){<li>{subdir_html(sd, 20)}</li>}, info.subdirs)}
              </ul>
            </div>
          </div>
          <div class="span9" id="charts">
          </div>
        </div>

      /* Charts */    
      options = [ {title: "Space usage per sub-directory"},
                  {width:400},
                  {height:400},
                ];

      data = GCharts.DataTable.make_simple(
          ("directory","size"),
          List.cons(("(current dir)", info.dotslash_size),
                    List.fold(function(e, l){ match(e.total_size) {
                    case {none}: l
                    case {some: size}: List.cons((e.label, size), l)
                    }}, info.subdirs, [])
                   ));

      GCharts.draw({pie_chart}, "charts", data, options);
    }

    //this function should exist somewhere!
    function string_limit(string str, int lim) {
        lim = max(2, lim)
        if (String.length(str) > lim-2) {
            String.sub(0, lim-2, str)^".."
        } else str
    }

    function path_html(path, full_path) {
//        Log.info("path_html", "{path} {OpaSerialize.to_string(full_path)}");

        n = List.length(full_path);
        m = if (n == 0) 50 else 80 / n;

        function label_html(~{label, path_key}) {
            hlabel =
                if (label == "") {
                  <img src="resources/dropbox_logo.png" alt="Root" height="32" width="32" />
                } else {
                  <span>{string_limit(label, m)}</span>
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

    function human_readable_size(int bytes) { //TODO first decimal digit
        if (bytes < 1000000) {
                <span title="{bytes} bytes">{bytes / 1000} kB</span>
        } else if (bytes < 1000000000) {
                <span title="{bytes} bytes">{bytes / 1000000} mB</span>
        } else {
                <span title="{bytes} bytes">{bytes / 1000000000} gB</span>            
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
        #footer = <p>You are using {human_readable_percentage(ratio_used)} of the {human_readable_size(total)} of space available; {human_readable_percentage(ratio_shared)} of your files are shared. </p>
    }

    function default_footer_html() {
        <p>&copy; Mathieu Baudet 2012 -- CSS styles and layout based on Twitter Bootstrap</p>
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
