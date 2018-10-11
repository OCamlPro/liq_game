open Lwt
open Options

let delay_retry = 30. (* seconds *)

exception RequestError of int * string

let post ~data path =
  if !verbosity > 0 then
    Printf.eprintf "\nPOST to %s%s:\n--------------\n%s\n%!"
      !host path
      (* data; *)
      (Ezjsonm.to_string ~minify:false (Ezjsonm.from_string data));
  try
    EzierRequest.post !host path data >>= fun (status, json) ->
    if status <> 200 then raise (RequestError (status, json));
    if !verbosity > 0 then
      Printf.eprintf "\nNode Response %d:\n------------------\n%s\n%!"
        status
        (Ezjsonm.to_string ~minify:false (Ezjsonm.from_string json));
    return json
  with Curl.CurlException (code, i, s) (* as exn *) ->
     raise (RequestError (Curl.errno code, s))

let get path =
  if !verbosity > 0 then
    Printf.eprintf "\nGET to %s%s:\n--------------\n%!"
      !host path;
  try
    EzierRequest.get !host path >>= fun (status, json) ->
    if status <> 200 then raise (RequestError (status, json));
    if !verbosity > 0 then
      Printf.eprintf "\nNode Response %d:\n------------------\n%s\n%!"
        status
        (Ezjsonm.to_string ~minify:false (Ezjsonm.from_string json));
    return json
  with Curl.CurlException (code, i, s) (* as exn *) ->
    raise (RequestError (Curl.errno code, s))

(* get with retry *)
let request_get = get
let rec get path =
  Lwt.catch
    (fun () -> request_get path)
    (function
      | RequestError (code, msg) ->
        Format.eprintf "Error for %s : code %d, %s\n\
                        Waiting %f s before retrying...@."
          path code msg delay_retry;
        Lwt_unix.sleep delay_retry >>= fun () ->
        Format.eprintf "Retrying now.@.";
        get path
      | exn -> Lwt.fail exn)


let get_head_hash () =
  get "/chains/main/blocks/head/header" >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    Ezjsonm.find r ["hash"] |> Ezjsonm.get_string |> return
  with Not_found ->
    failwith "get_head_hash"

let get_block_timestamp block =
  get (Printf.sprintf "/chains/main/blocks/%s/header" block) >>= fun r ->
  let r = Ezjsonm.from_string r in
  try
    Ezjsonm.find r ["timestamp"] |> Ezjsonm.get_string |> return
  with Not_found ->
    failwith "get_block_timestamp"


let get_storage ~block contract =
  get (Printf.sprintf
         "/chains/main/blocks/%s/context/contracts/%s/storage"
       block contract) >>= fun r ->
  Ezjsonm.from_string r |> return
