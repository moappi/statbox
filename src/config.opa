/*
    Copyright © 2012 Mathieu Baudet

    This file is part of StatBox.

    StatBox is free software: you can redistribute it and/or modify it under the
    terms of the GNU General Public License, version 3, as published by
    the Free Software Foundation.

    StatBox is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
    more details <http://www.gnu.org/licenses/>.
*/

import stdlib.io.file

protected default_params = {
    name : "StatBox",
    host : {none},
    key : {none},
    secret : {none}
}

protected params = CommandLine.filter({
    title : "Application parameters",
    init : default_params,
    
    parsers : [{ CommandLine.default_parser with
                   names : ["--name", "-n"],
                 description : "Name of the application (default: '{default_params.name}'",
                 on_param : function(st) { parser {n=Rule.consume -> {no_params : {st with name : n}}}}
               },
               { CommandLine.default_parser with
                   names : ["--host", "-h"],
                 description : "Public name of the host server (example: 'foo.com')",
                 on_param : function(st) { parser {n=Rule.consume -> {no_params : {st with host : {some: n}}}}}
               },
               { CommandLine.default_parser with
                   names : ["--key", "-k"],
                   description : "Dropbox API key",
                 on_param : function(st) { parser {n=Rule.consume -> {no_params : {st with key : {some: n}}}}}
               },
               { CommandLine.default_parser with
                   names : ["--secret", "-s"],
                   description : "Dropbox API secret",
                 on_param : function(st) { parser {n=Rule.consume -> {no_params : {st with secret : {some: n}}}}}
               }
],

   anonymous: []
})

// FIXME: very basic
function get_string(s) {
    file = "data/{s}.txt"
    Log.error("init", "Trying to read missing parameter {s} from file {file}")
    String.trim(File.content(file))
}

exposed application_name = params.name

protected host = (params.host ? get_string("host"))

protected dropbox_config = {
    app_key : (params.key ? get_string("key")),
    app_secret : (params.secret ? get_string("secret"))
}

// FIXME share url definition with dispatcher below
protected dropbox_redirect_url = "http://{host}/dropbox/connect"
