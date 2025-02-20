(* This file is part of DBL, released under MIT license.
 * See LICENSE for details.
 *)

(** Operations on effects and effect rows *)

open TypeBase

type row_view =
  | RPure
  | RUVar of TVar.Perm.t * uvar
  | RVar  of tvar
  | RApp  of typ * typ
  | RCons of tvar * effrow

let pure = t_closed_effrow TVar.Set.empty

let singleton_row x =
  t_closed_effrow (TVar.Set.singleton x)

let io = singleton_row BuiltinType.tv_io

let cons x eff =
  let (xs, ee) = effrow_view eff in
  t_effrow (TVar.Set.add x xs) ee

let cons_eff e eff =
  let xs1 = effect_view e in
  let (xs2, ee) = effrow_view eff in
  t_effrow (TVar.Set.union xs1 xs2) ee

let view eff =
  let (xs, ee) = effrow_view eff in
  match TVar.Set.choose_opt xs with
  | Some x -> RCons(x, t_effrow (TVar.Set.remove x xs) ee)
  | None ->
    begin match ee with
    | EEClosed -> RPure
    | EEUVar(p, u) -> RUVar(p, u)
    | EEVar x -> RVar x
    | EEApp(tp1, tp2) -> RApp(tp1, tp2)
    end

let view_end eff =
  snd (effrow_view eff)

let is_pure eff =
  match effrow_view eff with
  | (xs, EEClosed) -> TVar.Set.is_empty xs
  | _ -> false
