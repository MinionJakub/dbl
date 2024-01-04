(* This file is part of DBL, released under MIT license.
 * See LICENSE for details.
 *)

(** Additional environment used in type-checking definition blocks. It stores
  information about declared named implicits. *)

(* Author: Piotr Polesiuk, 2023,2024 *)

open Common

type t

(** List of implicit that can be generalized. It can be created by
  [begin_generalize] function and consumed by [end_generalize] *)
type implicit_list

(** Empty environment *)
val empty : t

(** Prepare environment to generalizing implicit parameters: it add implicit
  parameters to the environment. *)
val begin_generalize : Env.t -> t -> Env.t * implicit_list

(** Get a list of implicits, that were used, and therefore, should be
  generalized. *)
val end_generalize_pure : implicit_list -> (S.name * T.var * T.typ) list

(** Ensure, that no implicits on a given list were used. *)
val end_generalize_impure : implicit_list -> unit

(** Extend environment with a declaration of implicit *)
val declare_implicit : t -> S.name -> t

(** Shadow existing implicit name *)
val shadow : t -> S.name -> t

(** Extend environment with a polymorphic identifier. If it is a name, then
  it will be shadowed in implicit environment *)
val add_poly_id : Env.t -> t -> S.ident -> T.scheme -> Env.t * t * T.var