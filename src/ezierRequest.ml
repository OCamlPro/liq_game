open Lwt

let writer_callback a d =
  Buffer.add_string a d;
  String.length d

let initialize_connection host path =
  let url = Printf.sprintf "%s%s" host path in
  let r = Buffer.create 16384
  and c = Curl.init () in
  Curl.set_timeout c 30;      (* Timeout *)
  Curl.set_sslverifypeer c false;
  Curl.set_sslverifyhost c Curl.SSLVERIFYHOST_EXISTENCE;
  Curl.set_writefunction c (writer_callback r);
  Curl.set_tcpnodelay c true;
  Curl.set_verbose c false;
  Curl.set_post c false;
  Curl.set_url c url; r,c

let post ?(content_type = "application/json") host path data =
  let r, c = initialize_connection host path in
  Curl.set_post c true;
  Curl.set_httpheader c [ "Content-Type: " ^ content_type ];
  Curl.set_postfields c data;
  Curl.set_postfieldsize c (String.length data);
  Curl_lwt.perform c >>= fun cc ->
  let rc = Curl.get_responsecode c in
  Curl.cleanup c;
  Lwt.return (rc, (Buffer.contents r))

let get ?(content_type = "application/json") host path =
  let r, c = initialize_connection host path in
  Curl.set_post c false;
  Curl.set_httpheader c [ "Content-Type: " ^ content_type ];
  Curl_lwt.perform c >>= fun cc ->
  let rc = Curl.get_responsecode c in
  Curl.cleanup c;
  Lwt.return (rc, (Buffer.contents r))
