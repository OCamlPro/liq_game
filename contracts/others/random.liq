[%%version 0.4]

contract type Game = sig
  type storage
  val%entry play : nat -> _
  val%entry finish : nat -> _
  val%entry fund : unit -> _
end

type storage = {
    game_contract = Game.instance;
    registered : bool;
  val%entry register : unit -> _
  val%entry gen : unit -> _
end
