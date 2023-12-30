(* This file is part of DBL, released under MIT license.
 * See LICENSE for details.
 *)

(** The first phase of desugaring and post-parsing *)

(* Author: Piotr Polesiuk, 2023 *)

open Lang.Surface

type let_pattern =
  | LP_Var of var * Raw.expr list
    (** Variable definition with a list of formal parameters. *)

  | LP_Name of name * Raw.expr list
    (** Name definition with a list of formal parameters. *)

  | LP_Pat of pattern
    (** Let definition with pattern-matching *)

let rec tr_type_expr (tp : Raw.type_expr) =
  let make data = { tp with data = data } in
  match tp.data with
  | TWildcard -> make TWildcard
  | TVar x    -> make (TVar x)
  | TPureArrow(tp1, tp2) ->
    make (TPureArrow(tr_type_expr tp1, tr_type_expr tp2))
  | TArrow(tp1, tp2, eff) ->
    make (TArrow(tr_type_expr tp1, tr_type_expr tp2, tr_type_expr eff))
  | TEffect(tps, ee) ->
    make (TEffect(List.map tr_type_expr tps, Option.map tr_type_expr ee))

(** Translate a simple pattern, i.e., pattern that cannot be applied to
  the list of parameters. This function makes sure, that the provided list
  of parameters is empty *)
let rec tr_simple_pattern (p : Raw.expr) ps =
  let make data = { p with data = data } in
  match ps, p.data with
  | [], EWildcard -> make PWildcard
  | [], EUnit     -> Error.fatal (Error.desugar_error p.pos)
  | [], EParen p  -> make (tr_pattern p []).data
  | [], EVar  x   -> make (PVar x)
  | [], EName n   -> make (PName n)
  | [], (ECtor _ | EFn _ | EApp _ | EDefs _ | EMatch _ | EHandle _
    | ERecord _) ->
    assert false
  | p1 :: _, _ ->
    Error.fatal (Error.invalid_pattern_arg p1.pos)

(** Translate a pattern. Argument [ps] is an accumulated list of subpatterns *)
and tr_pattern (p : Raw.expr) ps =
  let make data = { p with data = data } in
  match p.data with
  | EWildcard | EUnit | EParen _ | EVar _ | EName _ ->
    tr_simple_pattern p ps
  | ECtor c -> make (PCtor(make c, List.map (fun p -> tr_pattern p []) ps))
  | EApp(p, p1) -> tr_pattern p (p1 :: ps)

  | EFn _ | EDefs _ | EMatch _ | EHandle _ | ERecord _ ->
    Error.fatal (Error.desugar_error p.pos)

(** Translate an expression as a let-pattern. Argument [ps] is an accumulated
  list of formal parameters/subpatterns *)
let rec tr_let_pattern (p : Raw.expr) ps =
  match p.data with
  | EWildcard | EUnit | EParen _ | ECtor _ -> LP_Pat (tr_pattern p ps)
  | EVar  x -> LP_Var(x, ps)
  | EName n -> LP_Name(n, ps)
  | EApp(p, p1) -> tr_let_pattern p (p1 :: ps)

  | EFn _ | EDefs _ | EMatch _ | EHandle _ | ERecord _ ->
    Error.fatal (Error.desugar_error p.pos)

(** Translate a formal parameter of a function *)
let tr_function_arg (arg : Raw.expr) =
  match arg.data with
  | EWildcard -> "_"
  | EVar x    -> x
  | EUnit | EParen _ | EName _ | ECtor _ | EFn _ | EApp _ | EDefs _ | EMatch _
  | EHandle _ | ERecord _ ->
    Error.fatal (Error.desugar_error arg.pos)

(** Translate a function, given a list of formal parameters *)
let rec tr_function args body =
  match args with
  | [] -> body
  | arg :: args ->
    { pos  = Position.join arg.pos body.pos;
      data = EFn(tr_function_arg arg, tr_function args body)
    }

let tr_poly_expr (e : Raw.expr) =
  let make data = { e with data = data } in
  match e.data with
  | EVar  x -> make (EVar  x)
  | EName n -> make (EName n)
  | ECtor c -> make (ECtor c)

  | EWildcard | EUnit | EParen _ | EFn _ | EApp _ | EDefs _ | EMatch _
  | EHandle _ | ERecord _ ->
    Error.fatal (Error.desugar_error e.pos)

let rec tr_expr (e : Raw.expr) =
  let make data = { e with data = data } in
  match e.data with
  | EUnit          -> make EUnit
  | EParen e       -> make (tr_expr e).data
  | EVar _ | EName _ | ECtor _ -> make (EPoly(tr_poly_expr e, []))
  | EFn(es, e)     -> make (tr_function es (tr_expr e)).data
  | EApp(e, { data = ERecord flds; _ }) ->
    make (EPoly(tr_poly_expr e, List.map tr_explicit_inst flds))
  | EApp(e1, e2)   -> make (EApp(tr_expr e1, tr_expr e2))
  | EDefs(defs, e) -> make (EDefs(tr_defs defs, tr_expr e))
  | EMatch(e, cls) -> make (EMatch(tr_expr e, List.map tr_match_clause cls))
  | EHandle(x, e, h) ->
    make (EHandle(x, tr_expr e, tr_h_expr h))
  | EWildcard | ERecord _ ->
    Error.fatal (Error.desugar_error e.pos)

and tr_match_clause (cl : Raw.match_clause) =
  let make data = { cl with data = data } in
  match cl.data with
  | Clause(pat, body) ->
    make (Clause(tr_pattern pat [], tr_expr body))

and tr_h_expr (h : Raw.h_expr) =
  let make data = { h with data = data } in
  match h.data with
  | HEffect(x, r, e) ->
    make (HEffect(x, r, tr_expr e))

and tr_explicit_inst (fld : Raw.field) =
  let make data = { fld with data = data } in
  match fld.data with
  | FldName n ->
    make (IName(n, make (EPoly(make (EName n), []))))
  | FldNameVal(n, e) ->
    make (IName(n, tr_expr e))

and tr_def (def : Raw.def) =
  let make data = { def with data = data } in
  match def.data with
  | DLet(p, e) ->
    begin match tr_let_pattern p [] with
    | LP_Var(x, args) ->
      make (DLet(x, tr_function args (tr_expr e)))
    | LP_Name(n, args) ->
      make (DLetName(n, tr_function args (tr_expr e)))
    | LP_Pat p -> make (DLetPat(p, tr_expr e))
    end
  | DImplicit n    -> make (DImplicit n)
  | DData(x, cs)   -> make (DData(x, List.map tr_ctor_decl cs))

and tr_defs defs = List.map tr_def defs

and tr_ctor_decl (d : Raw.ctor_decl) =
  let make data = { d with data = data } in
  match d.data with
  | CtorDecl(name, tps) -> make (CtorDecl(name, List.map tr_type_expr tps))

let tr_program (p : Raw.program) =
  let make data = { p with data = data } in
  make (EDefs(tr_defs p.data, make EUnit))
