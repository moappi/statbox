import stdlib.themes.bootstrap
import stdlib.widgets.bootstrap

import stdlib.tools.gcharts

WB = WBootstrap
GC = GCharts

/* "Model" to be rendered by ViewLib */

type ViewLib.login = { string logged } or { unlogged }

type ViewLib.path = string // current folder path-key (lowercase, begins with "/" except for root_path="")

type ViewLib.user_info = Dropbox.quota_info

type ViewLib.content = { welcome } or { error } or { ViewLib.path folder, ViewLib.user_info user_info } or { refreshing }

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
    @async client function set_login(ViewLib.login value) {
        Log.info("set_login", "{value}");
        ClientReference.set(viewlib_login, value)
        render_login();
    }

    @async client function set_content(ViewLib.content value) {
        old_value = ClientReference.get(viewlib_content);
        ClientReference.set(viewlib_content, value);

        Log.info("set_content", "{old_value} {value}"); // DO NOT REMOVE: Opa seems to need this to compile equality tests propertly !!

        (same_path, same_info) = 
            match((old_value, value)) {
            case ({folder: path1, user_info : info1}, {folder: path2, user_info : info2}):
                ((path1 == path2 && Map.mem(path2, ClientReference.get(viewlib_data))), (info1 == info2))
                // second condition Map.mem(..) on path is meant in particular to trigger a push_data if the map has been flushed 
            case ({welcome}, {welcome}): (true, true)
            case ({error}, {error}): (true, true)
            case ({refreshing}, {refreshing}): (true, true)
            default: (false, false)
                // N.B. we don't make precise all the cases for the footer
            }

        Log.info("set_content", "{value} => {same_path}, {same_info}");

        if (same_path == false) render_contentframe();
        if (same_info == false) render_footer();
        set_anchor(value);
    }

    @async client function set_data(string path, ViewLib.folder_info value) {

        go =
            match (Map.get(path, ClientReference.get(viewlib_data))) {
            case {none}:true
            case {some: val}: (value != val)
            } // TODO: use a timestamp rather than equality testing

        Log.info("set_data", "{path} => {go}");

        if (go) {
            ClientReference.set(viewlib_data, Map.add(path, value, ClientReference.get(viewlib_data)));

            match(ClientReference.get(viewlib_content)) {
            case {folder: path2 ...}: if (path == path2) render_contentframe();
            default: void
            }
        }
    }

    @async client function flush_data() {
        ClientReference.set(viewlib_data, Map.empty);
    }

    function render_login() {
        Log.info("render_login", "{ClientReference.get(viewlib_login)}");
        #login = ViewMake.login_html(ClientReference.get(viewlib_login))
    }

    function render_charts(ViewLib.folder_info info) {
        Log.info("render_charts", "{info}");
        /* Charts */    
        options = [ {title: "Space usage per sub-directory"},
                    {width:450},
                    {height:400},
                  ];

        data = GCharts.DataTable.make_simple(
            ("directory","size"),
            List.cons((ViewMake.current_path, info.dotslash_size),
                      List.fold(function(e, l){ match(e.total_size) {
                      case {none}: l
                      case {some: size}: List.cons((e.label, size), l)
                      }}, info.subdirs, [])
                     ));
        
        GCharts.draw({pie_chart}, "charts", data, options);
    }

    function render_footer() {
        Log.info("render_footer", "{ClientReference.get(viewlib_content)}");
        #footer = ViewMake.footer_html(ClientReference.get(viewlib_content))
    }


    function render_contentframe() {

        function is_incomplete({~total_size ...}) {
            match (total_size) {
            case {some:s}: false
            case {none}: true
            }
        }

        Log.info("render_contentframe", "{ClientReference.get(viewlib_content)}");
        match(ClientReference.get(viewlib_content)) {
        case {folder: path ...}:
            m = ClientReference.get(viewlib_data)
            if (Map.mem(path, m) == false) {
                Log.info("ViewLib", "missing data for path {path}: requesting server");
                ServerLib.push_data(path)
            } else {
                match (Map.get(path, m)) {
                case {some: info}:
                    #content = ViewMake.folder_html(path, info);
                    if (info.total_size == {none}
                        || List.exists(is_incomplete, info.subdirs))
                    {
                        Log.info("ViewLib.folder_html", "incomplete stats: flushing data");
                        ViewLib.flush_data();                        
//                        ViewMake.make_data_refresh_loop(2000); // broken??
                    }
                    render_charts(info) // !!
                default: void
                }
            }
        case {welcome}:
            #content = ViewMake.welcome_html();

        case {error}:
            #content = ViewMake.error_html()

        case {refreshing}:
            #content = ViewMake.refresh_html()

        }
    }

    function set_anchor(ViewLib.content content) {
        match (content) {
        case ({folder:path ...}):
            epath = encode_string(path)
            if (Client.Anchor.get_anchor() != epath) {
                Client.Anchor.set_anchor(epath)
            } else {
                Log.info("set_anchor", "skipping not changing anchor {encode_string(path)}")
            }
        default: Client.Anchor.set_anchor("")
        }
    }

    // Ocaml and javascript binding
    encode_string = %% encode.encode_string %%
    decode_string = %% encode.decode_string %%

    function make_link(xhtml label, string path_key) {
        path = encode_string(path_key);
        Xhtml.add_attribute_unsafe("href", "#{path}", <a>{label}</a>)
    }

    client function process_anchor(string anchor) {
        path = decode_string(anchor);
        Log.info("process_anchor", path);
        match (ClientReference.get(viewlib_content)) {
        case {~folder, ~user_info}:
            if (path != folder) {
                m = ClientReference.get(viewlib_data)
                // if we have the info locally, we agressively switch 
                if (Map.mem(path, m) == true) {
                    Log.info("process_anchor", "data already present");
                    ClientReference.set(viewlib_content, {folder:path, ~user_info});
                    render_contentframe();
                } else {
                    Log.info("process_anchor", "missing data");
                }
                // then, and in any case, we tell the server we wanted to move
                Log.info("process_anchor", "updating server");
                ServerLib.move_to_path(path)
            }
        default: Client.Anchor.set_anchor("") // not connected => we ignore anchors
        }
    }

    client function initial_setup(ViewLib.login login, ViewLib.content content, option(ViewLib.folder_info) current_folder_data) {
        // update client's state right away
        ClientReference.set(viewlib_login, login);
        ClientReference.set(viewlib_content, content);
        set_anchor(content);
        match ((content, current_folder_data)) {
        case ({folder:path ...}, {some:info}):
            ClientReference.set(viewlib_data, Map.add(path, info, ClientReference.get(viewlib_data)));
            render_charts(info);
        default: void
        };
        actor = ViewActor.make()
        ServerLib.register_actor(actor);
        ignore(Client.Anchor.add_handler(process_anchor))
        ViewMake.make_hard_refresh_loop(60000);
    }

}

// pure functions to construct Html
module ViewMake {

    function login_html(login) {
            match(login){
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
    }

    function size_opt_html(sizeopt) {
        match(sizeopt){
        case {none}: <p>??</p>
        case {some:size}: human_readable_size(size)
        }
    }

    current_path = "[files in current dir.]"

    function folder_html(string path, ViewLib.folder_info info) {

        function subdir_html({~label, ~path_key, ~total_size}) {
             <tr>
                <td>{ViewLib.make_link(<span>{string_limit(label, 45)}</span>, path_key)}</td>
                <td class="pull-right">{size_opt_html(total_size)}</td>
            </tr>
        }

        // reverse order, unknown size last
        function compare_subdir({~total_size ...}) {
            match (total_size) {
            case {some:s}: (-s)
            case {none}: 1
            }
        }

        /* navigation */
       <div class="row" id="pathnav">
          <div class="span12">{path_html(path, info.full_path)}</div>
        </div>
            <div class="row">
            <div class="well span5" id="navigation">
            <table class="table">
            {List.map(function(sd){subdir_html(sd)}, List.sort_by(compare_subdir, info.subdirs))}
        {if (info.counter != List.length(info.subdirs)) { subdir_html({label:current_path, path_key:path, total_size:{some: info.dotslash_size}})}else { <></> } }
            <tr><td><h4>{info.counter} elements</h4></td>
            <td class="pull-right"><h4>{size_opt_html(info.total_size)}</h4></td></tr>
            </table>
          </div>
          <div class="span5" id="charts">
          </div>
       </div>
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
            Log.info("debug", "Making element {label} {path_key} in breadcrumb.");
            hlabel =
                if (label == "") {
                  <img src="resources/dropbox_logo.png" alt="Root" height="32" width="32" />
                } else {
                  <span>{string_limit(label, m)}</span>
                }
            ha =  ViewLib.make_link(hlabel, path_key)
                  <+> <span class="divider">/</span>
            if (path_key == path) { // last one?
                  <li class="active">{ha}</li>
            } else {
                  <li>{ha}</li>
            }
        }

        <ul class="breadcrumb">
            {List.map(label_html, full_path)}
            <li class="pull-right">
            <a onclick={function(_){ ViewLib.flush_data(); ServerLib.refresh_content(false)} }>
            <img src="resources/refresh.png" alt="refresh" height="32" width="32" />
            </a>
            </li>
        </ul>
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

    function user_info_html(Dropbox.quota_info {~shared, ~normal, ~total}) {
        s = Float.of_int(shared)
        n = Float.of_int(normal)
        t = Float.of_int(total)
        ratio_used = (s + n) / t
        ratio_shared = s / (s + n)

        // TODO: on-mouseover % => real size 
        // Or progress bar: <div class="progress"> <div class="bar" style="width: 60%;"></div></div>
        <p>You are using <b>{human_readable_percentage(ratio_used)}</b> of the <b>{human_readable_size(total)}</b> of space available. <b>{human_readable_percentage(ratio_shared)}</b> of your files are shared. </p>
    }

    function default_footer_html() {
        <p>&copy; Mathieu Baudet 2012 -- CSS styles and layout based on Twitter Bootstrap</p>
    }

    function footer_html(ViewLib.content content) {
        match(content) {
        case {user_info: info ...}: user_info_html(info)
        default: default_footer_html()
        }
    }

    function welcome_html() {
        <div class="hero-unit">
        <h1>Welcome to {application_name}</h1>
        <p>Sign in with your <a href="http://www.dropbox.com">Dropbox</a> account to see your file statistics.</p>
        <p><a class="btn btn-primary btn-large" onclick={function(_){ServerLib.sign_in()}}>Sign in</a></p>
            <img src="resources/screenshot5.png" alt="screenshot" hspace="20%">
        </div>
    }

    function error_html() {
      <div class="alert alert-error">
        <h1>Oups</h1>
        <p>An error occur during the connection with Dropbox. Please sign in again.</p>
        <p><a class="btn btn-primary btn-large" onclick={function(_){ServerLib.sign_in()}}>Sign in</a></p>
      </div>
    }

    function make_soft_refresh_loop(t) {
        recursive function loop() {
            if (ClientReference.get(viewlib_content) == {refreshing}) {
                ServerLib.push_content();
                Log.info("refresh_loop", "hard");
                ignore(Client.setTimeout(loop, t));
            }
        }
        loop();
    }

    function make_data_refresh_loop(t) {
        recursive function loop() {
            if (ClientReference.get(viewlib_content) == {refreshing}) {
                ViewLib.flush_data();
                ServerLib.push_content();
                Log.info("refresh_loop", "data");
                ignore(Client.setTimeout(loop, t));
            }
        }
        ignore(Client.setTimeout(loop, t));
    }

    // FIXME: we may to cap the number of hard refresh for all the instances of a same user..
    function make_hard_refresh_loop(t) {
        recursive function loop() {
            match (ClientReference.get(viewlib_content)) {
            case {folder:_ ...}:
                ServerLib.refresh_content(true);
                Log.info("refresh_loop", "soft");
            default: void
            }
            ignore(Client.setTimeout(loop, t));         
        }
        ignore(Client.setTimeout(loop, t));
    }

    function refresh_html() {
        <div class="hero-unit" onready={function(_){make_soft_refresh_loop(1000)}}>
        <h2>Thanks for using {application_name}</h2>
        <h3>Your file information are being processed, and statistics will be available soon.</h3>
        </div>
    }

    function contentframe_html(ViewLib.content content, option(ViewLib.folder_info) current_folder_data) {
        match(content) {
        case {folder: path, ...}:
                match (current_folder_data) {
                case {some: info}:
                    ViewMake.folder_html(path, info)
                default: //impossible
                    ViewMake.error_html()
                }
        case {welcome}:
            ViewMake.welcome_html();

        case {error}:
            ViewMake.error_html()

        case {refreshing}:
            ViewMake.refresh_html();
        }
    }

    // server side construction of the initial main view
    // we only use the entry 'content.folder' (if any) from the data map
    function page_html(ViewLib.login login, ViewLib.content content, option(ViewLib.folder_info) current_folder_data) {
    <div class="navbar navbar-fixed-top" id="view" onready={function(_){
        ViewLib.initial_setup(login, content, current_folder_data);
    }}>
      <div class="navbar-inner">
        <div class="container">
          <a class="brand" href="#">{application_name}</a>
            <span id="login" class="pull-right">{
                login_html(login)
            }</span>
        </div>
      </div>
    </div>
    <div class="container">
      <div class="row" id="content">
            {contentframe_html(content, current_folder_data)}
      </div>
      <hr>
      <footer class="footer" id="footer">
            {footer_html(content)}
      </footer>
    </div>
    }
}

/* quick actor interface for the asynchronous function(s) set_* above to work around a limitation of UserContext & SizeDaemons */

type ViewActor.msg = { ViewLib.content set_content } // possibly every set_*

type ViewActor.chan = Session.channel(ViewActor.msg)

module ViewActor {

    client function make() {
        function on_msg(void _v, { set_content: content }) {
            ViewLib.flush_data();
            ViewLib.set_content(content);
            {unchanged}
        }
     
        Session.make(void, on_msg);
    }

    function set_content_and_flush_data(ViewActor.chan chan, content) {
        Session.send(chan, {set_content:content})
    }
}