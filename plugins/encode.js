##register encode_string : string -> string
  ##args(str)
  {
    return encodeURI(str);
  }

##register decode_string : string -> string
  ##args(str)
  {
    return decodeURI(str);
  }
