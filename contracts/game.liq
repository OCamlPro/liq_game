[%%version 0.4]

type game = {
  number : nat;
  payed : tez;
  player : UnitContract.instance;
}

type storage = {
  game : game option;
  trusted_server : address;
}

let%init storage (trusted_server : address) =
  { game = (None : game option); trusted_server }

let%entry play (number : nat) storage =
  if number > 100p then failwith "number must be <= 100";
  if 2p * Current.amount () > Current.balance () then
    failwith "I don't have enough money for this bet";
  match storage.game with
  | Some g ->
    failwith ("Game already started with", g)
  | None ->
    let player = match UnitContract.at (Current.sender ()) with
      | None -> failwith "Sender must call with a UnitContract.instance"
      | Some c -> c in
    let payed = Current.amount () in
    let storage = storage.game <- Some { number; payed; player } in
    (([] : operation list), storage)

let%entry finish (random_number : nat) storage =
  let random_number = match random_number / 101p with
    | None -> failwith "Random number must be <= 100"
    | Some (_, r) -> r in
  if Current.sender () <> storage.trusted_server then
    failwith ("Random numbers cannot be generated");
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
