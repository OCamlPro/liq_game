[%%version 0.4]

contract type Game = sig
  type storage
  val%entry play : number:nat -> _
  val%entry finish : random_number:nat -> _
  val%entry fund : _p:unit -> _
end

contract Random = struct

  type storage = {
    registered : bool;
    trusted_server : address;
    game_contract : Game.instance;
  }


  let%entry register (_p : unit) (storage : storage) =
    let storage = storage.registered <- true in
    ([] : operation list), storage

  let%entry gen (random_number : nat) storage =
    if Current.sender () <> storage.trusted_server then
      failwith ("Random numbers cannot be generated");
    let storage = storage.registered <- false in
    [ storage.game_contract.finish random_number ~amount:0tz ], storage

end

type game = {
  number : nat;
  payed : tez;
  player : UnitContract.instance;
}

type storage = {
  game : game option;
  random_addr : address option;
}

let%init storage : storage = { game = None; random_addr = None }

let[@inline] initialize_random_contract (s : storage) =
  match s.random_addr with
  | Some r -> (r, s, (None : operation option))
  | None ->
    let dummy_key_hash = tz1NfNNPhwT6CHFRpaU89HR7pDQHAKj1gj1B in
    let deploy_random, random_addr =
      Contract.create
        ~manager:dummy_key_hash
        ~delegate:(None : key_hash option)
        ~spendable:false
        ~delegatable:false
        ~amount:0tz
        ~storage:{
          Random.game_contract = Contract.self ();
          Random.registered = true;
          Random.trusted_server =
            (tz1NfNNPhwT6CHFRpaU89HR7pDQHAKj1gj1B : address);
        }
        (contract Random) in
    let s = s.random_addr <- Some random_addr in
    (random_addr, s, Some deploy_random)


let%entry play (number : nat) storage =
  if number > 100p then failwith "number must be <= 100";
  let random_addr, storage, maybe_deploy =
    initialize_random_contract storage in
  match storage.game with
  | Some g ->
    failwith ("Game already started with", g)
  | None ->
    let player = match UnitContract.at (Current.sender ()) with
      | None -> failwith "Must call with a UnitContract.instance"
      | Some c -> c in
    let payed = Current.amount () in
    let storage = storage.game <- Some { number; payed; player } in
    let ops = match maybe_deploy with
      | None ->
        let random_contract = match Random.at random_addr with
          | Some r -> r
          | None -> failwith () in
        let wait_for_random_op = random_contract.register () ~amount:0tz in
        [ wait_for_random_op ]
      | Some deploy_op -> [ deploy_op ] in
    (ops, storage)

let%entry finish (random_number : nat) storage =
  match storage.game with
  | None -> failwith "No game already started"
  | Some game ->
    let ops =
      if random_number < game.number then
        (* Loose *)
        ([] : operation list)
      else
        (* Win *)
        let gain = match (game.payed * game.number / 100p) with
          | None -> 0tz
          | Some (g, _) -> g in
        let reimbursed = game.payed + gain in
        [ game.player.main () ~amount:reimbursed ]
    in
    let storage = storage.game <- (None : game option) in
    (ops, storage)

(* accept funds *)
let%entry fund (_p : unit) storage =
  ([] : operation list), storage
