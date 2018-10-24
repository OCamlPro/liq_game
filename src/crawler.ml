open Lwt
open Options
open Request

(* module Ezjsonm = struct
 *   include Ezjsonm
 *   let find json l =
 *     try find json l with
 *       Not_found -> Format.eprintf "%s@." (String.concat "." l); raise Not_found
 * end *)


let chunk_size = ref 100

let _ =
  Random.init (Unix.time () +. (Sys.time () *. 100000.) |> int_of_float)

let int_of_michelson_json json =
  Ezjsonm.(find json ["int"] |> get_string) |> int_of_string

let int64_of_michelson_json json =
  Ezjsonm.(find json ["int"] |> get_string) |> Int64.of_string

let string_of_michelson_json json =
  Ezjsonm.(find json ["string"] |> get_string)

let bytes_of_michelson_json json =
  Ezjsonm.(find json ["bytes"] |> get_string)

let bool_of_michelson_json json =
  Ezjsonm.(find json ["prim"] |> get_string) |> function
  | "True" -> true
  | "False" -> false
  | _ -> assert false

let unit_of_michelson_json json =
  assert Ezjsonm.(find json ["prim"] |> get_string = "Unit");
  ()

let pair_of_michelson_json left right json =
  assert Ezjsonm.(find json ["prim"] |> get_string = "Pair");
  Ezjsonm.(find json ["args"] |> get_pair left right)

type ('a, 'b) variant = Left of 'a | Right of 'b

let one_arg dec json =
  match Ezjsonm.get_list (fun x -> x) json with
  | [x] -> dec x
  | _ -> assert false

let variant_of_michelson_json left right json =
  match Ezjsonm.(find json ["prim"] |> get_string) with
  | "Left" -> Left (Ezjsonm.(find json ["args"] |> one_arg left))
  | "Right" -> Right (Ezjsonm.(find json ["args"] |> one_arg right))
  | _ -> assert false

let option_of_michelson_json some json =
  match Ezjsonm.(find json ["prim"] |> get_string) with
  | "None" -> None
  | "Some" -> Some (Ezjsonm.(find json ["args"] |> one_arg some))
  | _ -> assert false


type gameparam =
  | Play of int * string
  | Finish of int
  | Fund

type game = {
  number : int;
  payed : int64;
  player : string;
}

type gamestorage = {
  game : game option;
  rand_addr : string option;
}

type randomstorage = {
  registered : bool;
  trusted_server : string;
  game_contract : string;
}

let random_storage_of_json json =
  let registered, (trusted_server, game_contract) =
    pair_of_michelson_json
      bool_of_michelson_json
      (pair_of_michelson_json
         string_of_michelson_json
         string_of_michelson_json)
      json in
  { registered ; trusted_server; game_contract }

let gameparam_of_json json =
  match
    variant_of_michelson_json
      (pair_of_michelson_json
         int_of_michelson_json
         string_of_michelson_json)
      (variant_of_michelson_json
         int_of_michelson_json
         unit_of_michelson_json)
      json
  with
  | Left (n, k) -> Play (n, k)
  | Right (Left n) -> Finish n
  | Right (Right ()) -> Fund

let gamestorage_of_json json =
  let (g, rand_addr) =
    pair_of_michelson_json
      (option_of_michelson_json
         (pair_of_michelson_json
            int_of_michelson_json
            (pair_of_michelson_json
               int64_of_michelson_json
               string_of_michelson_json)))
      (option_of_michelson_json
         string_of_michelson_json)
      json in
  match g with
  | None -> { game = None; rand_addr }
  | Some (number, (payed, player)) ->
    { game = Some { number; payed; player };
      rand_addr }

let liq_command () =
  Printf.sprintf "liquidity \
                  --private-key %s \
                  --tezos-node %s \
                  --fee 0tz \
                  contracts/game.liq"
    !sk !host

let call addr entry parameter =
  Printf.sprintf "%s --call %s %s %s"
    (liq_command ()) addr entry parameter
  |> (fun c -> Format.printf "LIQUIDITY: %s@." c; c)
  |> Sys.command
  |> ignore

let get_storage block_hash contract =
  get (Printf.sprintf "/chains/main/blocks/%s/context/contracts/%s/storage"
         block_hash contract) >|= Ezjsonm.from_string

let gen_random_number block_hash =
  let rand = (string_of_int (Random.int 101) ^ "p") in
  call !game_contract_hash "finish" rand;
  return_unit

let rec update_of_one_transaction ?(internal=false) block_hash tr_json =
  if Ezjsonm.(find tr_json ["kind"] |> get_string <> "transaction") then
    return_unit
  else
    let destination = Ezjsonm.(find tr_json ["destination"] |> get_string) in
    let source = Ezjsonm.(find tr_json ["source"] |> get_string) in
    let status_path =
      if internal then ["result"; "status"]
      else ["metadata" ; "operation_result"; "status"] in
    let status =
      Ezjsonm.(find tr_json status_path |> get_string) in
    begin
      if status <> "applied"
      || destination <> !game_contract_hash
      then return_unit
      else
        let parameters = Ezjsonm.(find tr_json ["parameters"]) in
        let param = gameparam_of_json parameters in
        match param with
        | Play (number, _) ->
          Format.printf "%s played %d@." source number;
          gen_random_number block_hash
        | Finish rand ->
          Format.printf "Finishing game with random number %d@." rand;
          return_unit
        | Fund ->
          Format.printf "Funds added to game contract@.";
          return_unit
    end >>= fun () ->
    if internal then return_unit
    else
      try
        let internal_operations =
          Ezjsonm.find tr_json ["metadata" ; "internal_operation_results"] in
        let trs = Ezjsonm.get_list (fun tr -> tr) internal_operations in
        Lwt_list.iter_s
          (update_of_one_transaction ~internal:true block_hash) trs
      with Not_found -> return_unit

let crawl_one_transaction block_hash tr_json =
  update_of_one_transaction block_hash tr_json

let crawl_one_operation block_hash op_json =
  let contents = Ezjsonm.(find op_json ["contents"] |> get_list (fun x -> x)) in
  Lwt_list.iter_s (crawl_one_transaction block_hash) contents

let crawl_operations block_hash ops =
  Ezjsonm.get_list (fun op -> op) ops
  |> Lwt_list.iter_s (crawl_one_operation block_hash)

let crawl_block block_hash =
  Printf.eprintf "%s\n%!" block_hash;
  get (Printf.sprintf "/chains/main/blocks/%s/operations/3" block_hash)
  >>= fun r ->
  let ops = Ezjsonm.from_string r in
  let info_file = "info.json" in
  let info_json =
    try
      let ic = open_in info_file in
      let json = Ezjsonm.from_channel ic in
      close_in ic;
      json
    with _ -> Ezjsonm.dict [] in
  get_block_timestamp block_hash >>= fun timestamp ->
  let info_json =
    Ezjsonm.(update info_json ["last_updated"] (Some (string timestamp))) in
  crawl_operations block_hash ops >>= fun () ->
  let oc = open_out info_file in
  Ezjsonm.to_channel oc (match info_json with `O v -> `O v | _ -> assert false);
  close_out oc;
  return_unit

let rec blocks_to_handle acc head =
  get (Printf.sprintf "/chains/main/blocks?length=%d&head=%s"
         !chunk_size head) >>= fun r ->
  let r = Ezjsonm.from_string r in
  let l = Ezjsonm.(get_list (get_list get_string)) r in
  let l = List.flatten l in
  let exception Stop of string list in
  try
    let acc =
      List.fold_left (fun acc h ->
          if h = !last_handled_block then raise (Stop acc);
          h :: acc
        ) acc l
    in
    let head, acc = match acc with
      | x :: r -> x, r
      | [] -> assert false in
    blocks_to_handle acc head
  with Stop acc -> return acc

let crawl () =
  get_head_hash () >>= fun head ->
  blocks_to_handle [] head >>= fun blocks ->
  Lwt_list.iter_s crawl_block blocks >>= fun () ->
  begin match List.rev blocks with
  | [] -> ()
  | b :: _ -> Options.last_handled_block := b
  end;
  return_unit


let main () =
  let rec loop () =
    Lwt_unix.sleep 3.0 >>= crawl >>= loop in
  (* first crawl *)
  crawl () >>= fun () ->
  chunk_size := 2;
  loop ()

let () =
  init_config "config.json" (* default *);
  Arg.parse (Arg.align [
      "--config", Arg.String init_config,
      "<file> Choose configuration file";
      "-v", Arg.Unit (fun () -> incr verbosity),
      " Increase verbosity level";
      "--contract", Arg.String (fun c -> game_contract_hash := c),
      "<hash> Specify contract to monitor";
      "--from", Arg.String (fun b -> last_handled_block := b),
      "<hash> Start monitoring at this block hash, usually orignation of \
       contract";
      "--node", Arg.String (fun h -> host := h),
      "<addr> Address of Tezos node";
    ])
    (fun _ -> ())
    {|Usage: image-bid [OPTIONS]

Start the crawler to monitor the Tezos blockchain and update an image file
accordingly.

Available options:|};

  Lwt_main.run (main ())
