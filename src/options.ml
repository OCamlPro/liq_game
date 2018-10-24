let verbosity = ref 0
let game_contract_hash = ref "$GAME_CONTRACT"
let last_handled_block = ref ""
let host = ref "http://127.0.0.1:8732"
let sk = ref "edsk"
(* let output = ref "image.png"
 * let image_size = 1000
 * let hide_file = ref "hide.json" *)

let set_option config option_ref option_name parse =
  try
    option_ref := Ezjsonm.find config [option_name] |> parse;
  with Not_found -> ()

let init_config config_file =
  let open Ezjsonm in
  let ic = open_in config_file in
  let config = Ezjsonm.from_channel ic in
  set_option config verbosity "verbosity" get_int;
  set_option config game_contract_hash "game_contract_hash" get_string;
  set_option config last_handled_block "origination_block" get_string;
  set_option config host "node" get_string;
  set_option config sk "private_key" get_string;
  (* set_option config output "output" get_string;
   * set_option config hide_file "hide_file" get_string; *)
  close_in ic