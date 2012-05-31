open Base

(* these functions originate from Opa's libbase *)

let chhxmp = Array.init 256 (fun i -> Printf.sprintf "%02X" i)
let pc_encode ch = "%"^(chhxmp.(Char.code ch))

(* https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/encodeURI *)
let is_url = function
  | 'a'..'z' -> true | 'A'..'Z' -> true | '0'..'9' -> true
  | '-' | '_' | '.' | '!' | '~' | '*' | '\'' |'(' | ')' -> true
  | ';' | ',' | '/' | '?' | ':' | '@' | '&' | '=' | '+' | '$' | '#' -> true
  | _ -> false

let encode_chars_filter ?(hint=(fun l -> (l + (l asr 4)))) is_char encode_char s =
  let l = String.length s in
  let b = Buffer.create (hint l) in
  let rec aux i j =
    if i < l
    then
      if is_char s.[i]
      then (Buffer.add_char b s.[i]; aux (i+1) (j+1))
      else
        let code = encode_char s.[i] in
        let clen = String.length code in
        Buffer.add_string b code; aux (i+1) (j+clen)
    else j
  in
  Buffer.sub b 0 (aux 0 0)

let http_unencode s =
  let l = String.length s in
  let r = String.copy s in
  let rec aux i j =
    if i < l
    then
      (match s.[i] with
       | '%' ->
           let k = i + 1 in
           if k + 1 < l
           then
             (match s.[k],s.[k+1] with
              | (ch1,ch2) when (Charf.is_hexf ch1 && Charf.is_hexf ch2) ->
                  (r.[j] <- Char.chr (Charf.c2h s.[k] s.[k+1]); aux (i+3) (j+1))
              | _ -> (r.[j] <- '%'; aux (i+1) (j+1)))
           else (r.[j] <- '%'; aux (i+1) (j+1))
       | ch -> (r.[j] <- ch; aux (i+1) (j+1)))
    else j
  in
  String.unsafe_sub r 0 (aux 0 0)

##register encode_string : string -> string
let encode_string s = encode_chars_filter is_url pc_encode s

##register decode_string : string -> string
let decode_string = http_unencode

