package custom.stdlib.apis.dropbox

/*
    Copyright © 2012 MLstate

    This file is part of OPA.

    OPA is free software: you can redistribute it and/or modify it under the
    terms of the GNU Affero General Public License, version 3, as published by
    the Free Software Foundation.

    OPA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public License for
    more details.

    You should have received a copy of the GNU Affero General Public License
    along with OPA.  If not, see <http://www.gnu.org/licenses/>.
*/
/*
 * Author    : Nicolas Glondu <nicolas.glondu@mlstate.com>
 * Updated by: Mathieu Baudet <mathieu.baudet@gmail.com>
 **/

/**
 * Dropbox generic API module (v1)
 *
 * @category api
 * @author Nicolas Glondu, 2011
 * @author Mathieu Baudet, 2012
 * @destination public
 */

import stdlib.apis.common
import stdlib.apis.oauth

/**
 * Dropbox configuration
 *
 * To obtain application credentials, visit:
 *  https://www.dropbox.com/developers/apps
 */
type Dropbox.conf = {
  app_key    : string
  app_secret : string
}

type Dropbox.credentials = {
  token  : string
  secret : string
}

type Dropbox.metadata_options = {
  file_limit      : int
  hash            : option(string)
  list            : bool
  include_deleted : bool
  rev             : option(int)
    //TODO: locale
}

type Dropbox.delta_options = {
  cursor          : option(string)
    //TODO: locale
}

type Dropbox.thumb_format = {jpeg} / {png}
type Dropbox.thumb_size =
    {small}  // 32x32
  / {medium} // 64x64
  / {large}  // 128x128
  / {s}      // 64x64
  / {m}      // 128x128
  / {l}      // 640x480
  / {xl}     // 1024x768

/* Types returned by API */

type Dropbox.common_metadata = {
  rev          : string
  thumb_exists : bool
  bytes        : int
  size         : string
  modified     : option(Date.date)
  path         : string
  icon         : string
  root         : string
  is_deleted   : bool
}

type Dropbox.file_metadata =
    { mime_type : string
      client_mtime : option(Date.date)
    }

/**
 * Note that an empty folder will have its [content] field
 * to [some([])] and that [none] for this field just means
 * that there was no information about the folder files.
 */
type Dropbox.folder_metadata =
    { contents : option(list(Dropbox.element))
      hash : string
     }

type Dropbox.element =
    { metadata : Dropbox.common_metadata
      kind : {file : Dropbox.file_metadata} / {folder : Dropbox.folder_metadata}
    }

type Dropbox.delta_entry = {
  path: string  // lowercase path
  metadata: option(Dropbox.element) //none = removed
}

type Dropbox.delta = {
  entries      : list(Dropbox.delta_entry)
  reset        : bool
  cursor       : string
  has_more     : bool
}

type Dropbox.quota_info = {
  shared : int
  normal : int
  total  : int
}

type Dropbox.info = {
  email         : string
  display_name  : string
  referral_link : string
  uid           : int
  country       : string
  quota_info    : Dropbox.quota_info
}

type Dropbox.url = {
  url : string
  expires : Date.date
}

type Dropbox.file = {
  content : binary
  mime_type : string
}

@private DBParse = {{

  /**
   * Example of date: Fri, 20 Jan 2012 16:18:23 +0000
   */
  build_date(str) =
    do Log.info("Parsing date", "{OpaSerialize.to_string(str)}")
    int_of_text(t) = Int.of_string(Text.to_string(t))
    n = parser k=[0-9] -> k
    nn = parser v=(n+) -> int_of_text(v)
    do_shift(forward,h,min) =
      d = { Duration.zero with ~forward ~h ~min } |> Duration.of_human_readable
      Date.advance(_, d)
    shift(forward,h,m) =
      do_shift(forward,int_of_text(h),int_of_text(m))
    tmz = parser
      | "Z" -> identity
      | "-" h=(n n) m=(n n) -> shift(true, h, m)
      | "-" h=(n n) ":" m=(n n) -> shift(true, h, m)
      | "+" h=(n n) m=(n n) -> shift(false, h, m)
      | "+" h=(n n) ":" m=(n n) -> shift(false, h, m)
      | .* -> identity
    mon = parser
      | "Jan" -> {january}
      | "Feb" -> {february}
      | "Mar" -> {march}
      | "Apr" -> {april}
      | "May" -> {may}
      | "Jun" -> {june}
      | "Jul" -> {july}
      | "Aug" -> {august}
      | "Sep" -> {september}
      | "Oct" -> {october}
      | "Nov" -> {november}
      | "Dec" -> {december}
    p = parser
      | (!n .)* d=nn " " m=mon " " y=nn " " h=nn ":" min=nn ":" s=nn " " tmz=tmz ->
        tmz(Date.build({year=y month=m day=d h=h min=min s=s}))
    match Parser.try_parse(p, str) with
    | {some=d} -> d
    | {none} ->
      do Log.error("build_date", "Failed to parse '{str}'")
      Date.now()

  build_quota(data) =
    do Log.info("Parsing quota", "{OpaSerialize.to_string(data)}")
    map = JsonOpa.record_fields(data) ? Map.empty
    int(name) = API_libs_private.map_get_int(name, map)
    { shared = int("shared")
      normal = int("normal")
      total  = int("quota")
    } : Dropbox.quota_info

  build_infos(data) =
    do Log.info("Parsing infos", "{OpaSerialize.to_string(data)}")
    map = API_libs_private.parse_json(data.content)
      |> JsonOpa.record_fields
      |> Option.default(Map.empty, _)
    int(name) = API_libs_private.map_get_int(name, map)
    str(name) = API_libs_private.map_get_string(name, map)
    quota_info =
      StringMap.get("quota_info", map) ? {Record=[]}:RPC.Json.json
      |> build_quota
    { ~quota_info
      email         = str("email")
      referral_link = str("referral_link")
      display_name  = str("display_name")
      uid           = int("uid")
      country       = str("country")
    } : Dropbox.info

  make_element(elt) : Dropbox.element =
    do Log.info("Parsing element", "{OpaSerialize.to_string(elt)}")
    map = JsonOpa.record_fields(elt) ? Map.empty
    int(name) = API_libs_private.map_get_int(name, map)
    str(name) = API_libs_private.map_get_string(name, map)
    bool(name) = API_libs_private.map_get_bool(name, map, false)
    modified =
      date_str = str("modified")
      if date_str == "" then none
      else some(build_date(date_str))
    metadata = {
      rev          = str("rev")
      thumb_exists = bool("thumb_exists")
      bytes        = int("bytes")
      size         = str("size")
      modified     = modified
      path         = str("path")
      icon         = str("icon")
      root         = str("root")
      is_deleted   = bool("is_deleted")
    }
    is_dir = bool("is_dir")
    if is_dir then
      contents : option(list(Dropbox.element)) =
        match StringMap.get("contents", map) with
        | {some={List=l}} ->
          some(List.map(make_element, l))
        | _ -> none
      hash = str("hash")
      {~metadata kind = {folder = {~contents ~hash}}}
    else
      mime_type = str("mime_type")
      client_mtime =
          date_str = str("client_mtime")
          if date_str == "" then none
          else some(build_date(date_str))
      {~metadata kind = {file = {~mime_type ~client_mtime}}}

  build_one_metadata(data) =
    do Log.info("Parsing one metadata", "{OpaSerialize.to_string(data)}")
    parsed = API_libs_private.parse_json(data.content)
    make_element(parsed)

  build_metadata_list(data) =
    do Log.info("Parsing metadata list", "{OpaSerialize.to_string(data)}")
    match API_libs_private.parse_json(data.content) with
    | {List=l} -> List.map(make_element, l)
    | _ -> []

  build_delta_entries(acc, ljson) =
    match ljson with
    | [] -> List.rev(acc)
    | [{ List = [{String = path}, ({Record = _} as jmetadata)] } | q] ->
      build_delta_entries([{ path=path
                             metadata={some=make_element(jmetadata)}
                          } | acc], q)
    | [{ List = [{String = path}] } | q]   ->
      build_delta_entries([{~path metadata={none}} | acc], q)
    | [{ List = [{String = path}, _] } | q ] ->
      build_delta_entries([{~path metadata={none}} | acc], q)
    | [ _ | q ] -> build_delta_entries(acc, q)

  build_delta(data) =
    do Log.info("Parsing delta entries", "{OpaSerialize.to_string(data)}");
    map = API_libs_private.parse_json(data.content)
      |> JsonOpa.record_fields
      |> Option.default(Map.empty, _)
    str(name) = API_libs_private.map_get_string(name, map)
    bool(name) = API_libs_private.map_get_bool(name, map, false)
    entries : list(Dropbox.delta_entry) =
        match StringMap.get("entries", map) with
        | {some={List=l}} -> build_delta_entries([], l)
        | _ -> []
    { entries = entries
      reset   = bool("reset")
      cursor = str("cursor")
      has_more = bool("has_more")
    } : Dropbox.delta
        
  build_url(data) =
    do Log.info("Parsing URL", "{OpaSerialize.to_string(data)}")
    map = API_libs_private.parse_json(data.content)
      |> JsonOpa.record_fields
      |> Option.default(Map.empty, _)
    str(name) = API_libs_private.map_get_string(name, map)
    { url     = str("url")
      expires = str("expires") |> build_date
    } : Dropbox.url

  build_file(data) =
    do Log.info("Parsing file", "{OpaSerialize.to_string(data)}")
    { content = data.content
      mime_type = data.mime_type
    } : Dropbox.file

}}

@private DBprivate(conf:Dropbox.conf) = {{

  DBOAuth(http_method) = OAuth({
    consumer_key      = conf.app_key
    consumer_secret   = conf.app_secret
    auth_method       = {HMAC_SHA1}
    request_token_uri = "https://api.dropbox.com/1/oauth/request_token"
    authorize_uri     = "https://www.dropbox.com/1/oauth/authorize"
    access_token_uri  = "https://api.dropbox.com/1/oauth/access_token"
    http_method       = http_method
    inlined_auth      = false
    custom_headers    = []
  } : OAuth.parameters)

// Mathieu: FIXME: Deal with error codes correctly in the functions below.
// An error code != 200 is not considered a failure... We should return a meaningful value based on the error code instead.

  wget(host, path, params, credentials:Dropbox.credentials, parse_fun) =
    uri = "{host}{path}"
    res = DBOAuth({GET}).get_protected_resource_2(uri, params, credentials.token, credentials.secret)
    match res with
    | {success=s} -> {success=parse_fun(s)}
    | {failure=f} -> {failure=f}

  wpost(host, path, params, credentials:Dropbox.credentials, parse_fun) =
    uri = "{host}{path}"
    res = DBOAuth({POST}).get_protected_resource_2(uri, params, credentials.token, credentials.secret)
    match res with
    | {success=s} -> {success=parse_fun(s)}
    | {failure=f} -> {failure=f}

  wput(host, path, mimetype:string, file:binary, params, credentials:Dropbox.credentials, parse_fun) =
    uri = "{host}{path}"
    res = DBOAuth({PUT=~{mimetype file}}).get_protected_resource_2(uri, params, credentials.token, credentials.secret)
    match res with
    | {success=s} -> {success=parse_fun(s)}
    | {failure=f} -> {failure=f}

}}

Dropbox(conf:Dropbox.conf) = {{

  // Note: V1 of the API
  @private api_host = "https://api.dropbox.com/1/"
  @private content_host = "https://api-content.dropbox.com/1/"
  @private DBP = DBprivate(conf)

  OAuth = {{

    get_request_token =
      DBP.DBOAuth({GET}).get_request_token

    build_authorize_url(token, callback_url) =
      "{DBP.DBOAuth({GET}).build_authorize_url(token)}&oauth_callback={Uri.encode_string(callback_url)}"

    connection_result =
      DBP.DBOAuth({GET}).connection_result

    get_access_token =
      DBP.DBOAuth({GET}).get_access_token

  }}

  Account = {{

    info(credentials) =
      DBP.wget(api_host, "account/info", [], credentials, DBParse.build_infos)

  }}

  default_metadata_options = {
    file_limit      = 10000
    hash            = none
    list            = true
    include_deleted = false
    rev             = none
  } : Dropbox.metadata_options

  Files = {{

    get(file_path:string, rev:option(int), credentials) =
      path = "files/{file_path}"
      params = match rev with
        | {none} -> []
        | {some=r} -> [("rev", Int.to_string(r))]
      DBP.wget(content_host, path, params, credentials, DBParse.build_file)

    put(file_path:string, mimetype, file:binary, overwrite, parent_rev:option(int), credentials) =
      path = "files_put/{file_path}"
      params = [
        ("overwrite", Bool.to_string(overwrite)),
      ] |> (
        match parent_rev with
        | {none} -> identity
        | {some=r} -> List.cons(("parent_rev", Int.to_string(r)), _)
      )
      //      do ignore(file) //Mathieu: strange useless line commented out
      DBP.wput(content_host, path, mimetype, file, params, credentials, DBParse.build_one_metadata)

    @private format_metadata_options(o:Dropbox.metadata_options) =
      [ ("file_limit", Int.to_string(o.file_limit)),
        ("list", Bool.to_string(o.list)),
        ("include_deleted", Bool.to_string(o.include_deleted)),
      ] |> (
        match o.hash with
          | {none} -> identity
          | {some=h} -> List.cons(("hash", h), _)
      ) |> (
        match o.rev with
          | {none} -> identity
          | {some=r} -> List.cons(("rev", Int.to_string(r)), _)
      )

    metadata(file_path:string, options, credentials) =
      path = "metadata/{file_path}"
      params = format_metadata_options(options)
      DBP.wget(api_host, path, params, credentials, DBParse.build_one_metadata)

    @private format_delta_options(o:Dropbox.delta_options) =
        match o.cursor with
          | {none} -> []
          | {some=h} -> [("cursor", h)]

    delta(options, credentials) =
      path = "delta"
      params = format_delta_options(options)
      DBP.wpost(api_host, path, params, credentials, DBParse.build_delta)

    /**
     * default: 10 - max: 1000
     */
    revisions(file_path:string, rev_limit:option(int), credentials) =
      path = "revisions/{file_path}"
      params = match rev_limit with
        | {none} -> []
        | {some=l} -> [("rev_limit", Int.to_string(l))]
      DBP.wget(api_host, path, params, credentials, DBParse.build_metadata_list)

    restore(file_path:string, rev, credentials) =
      path = "restore/{file_path}"
      params = [("rev", Int.to_string(rev))]
      DBP.wpost(api_host, path, params, credentials, DBParse.build_one_metadata)

    /**
     * default and max: 1000
     */
    search(file_path:string, query, include_deleted:bool, file_limit:option(int), credentials) =
      path = "search/{file_path}"
      params = [
        ("query", query),
        ("include_deleted", Bool.to_string(include_deleted)),
      ] |> (
        match file_limit with
        | {none} -> identity
        | {some=l} -> List.cons(("file_limit", Int.to_string(l)), _)
      )
      DBP.wget(api_host, path, params, credentials, DBParse.build_metadata_list)

    shares(file_path:string, credentials) =
      path = "shares/{file_path}"
      DBP.wpost(api_host, path, [], credentials, DBParse.build_url)

    media(file_path:string, credentials) =
      path = "media/{file_path}"
      DBP.wpost(api_host, path, [], credentials, DBParse.build_url)

    /**
     * Prefer [jpeg] for photos while [png] is better for
     * screenshots and digital art
     */
    thumbnails(file_path:string, format:Dropbox.thumb_format, size:Dropbox.thumb_size, credentials) =
      path = "thumbnails/{file_path}"
      format = match format with
        | {jpeg} -> "JPEG"
        | {png} -> "PNG"
      size = match size with
        | {small}  -> "small"
        | {medium} -> "medium"
        | {large}  -> "large"
        | {s}      -> "s"
        | {m}      -> "m"
        | {l}      -> "l"
        | {xl}     -> "xl"
      params = [
        ("format", format),
        ("size", size),
      ]
      DBP.wget(content_host, path, params, credentials, DBParse.build_file)

  }}

  FileOps = {{

    copy(root, from_path, to_path, credentials) =
      path = "fileops/copy"
      params = [
        ("root", root),
        ("from_path", from_path),
        ("to_path", to_path),
      ]
      DBP.wpost(api_host, path, params, credentials, DBParse.build_one_metadata)

    create_folder(root, path, credentials) =
      rpath = "fileops/create_folder"
      params = [
        ("root", root),
        ("path", path),
      ]
      DBP.wpost(api_host, rpath, params, credentials, DBParse.build_one_metadata)

    delete(root, path, credentials) =
      rpath = "fileops/delete"
      params = [
        ("root", root),
        ("path", path),
      ]
      DBP.wpost(api_host, rpath, params, credentials, DBParse.build_one_metadata)

    move(root, from_path, to_path, credentials) =
      path = "fileops/move"
      params = [
        ("root", root),
        ("from_path", from_path),
        ("to_path", to_path),
      ]
      DBP.wpost(api_host, path, params, credentials, DBParse.build_one_metadata)

  }}

}}
