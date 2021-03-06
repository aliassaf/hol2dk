(* ======================================================================================== *)
(*                 Proof-objects for HOL-light, exportation to Coq                          *)
(*                                                                                          *)
(*       Steven Obua, TU Mnchen, December 2004                                              *)
(*       Chantal Keller, Laboratoire d'Informatique de Polytechnique (France), January 2010 *)
(*                                                                                          *)
(*       based on Sebastian Skalberg's HOL4 proof-objects                                   *)
(* ======================================================================================== *)

#load "unix.cma";;
#load "depgraph.cma";;


module type Proofobject_primitives =
  sig

    type proof

    val proof_REFL : term -> proof
    val proof_TRANS : proof * proof -> proof
    val proof_MK_COMB : proof * proof -> proof
    val proof_ASSUME : term -> proof
    val proof_EQ_MP : proof -> proof -> proof
    val proof_IMPAS : proof -> proof -> proof
    val proof_DISCH : proof -> term -> proof
    val proof_DEDUCT_ANTISYM_RULE : proof * term -> proof * term -> proof
    val proof_BETA : term -> proof
    val proof_ABS : term -> proof -> proof
    val proof_INST_TYPE : (hol_type * hol_type) list -> proof -> proof
    val proof_INST : (term * term) list -> proof -> proof
    val proof_new_definition : string -> hol_type -> term -> proof
    val proof_CONJ : proof -> proof -> proof
    val proof_CONJUNCT1 : proof -> proof
    val proof_CONJUNCT2 : proof -> proof
    val proof_new_basic_type_definition :
      string -> string * string -> term * term -> proof -> proof
    val proof_SPEC : term -> proof -> proof
    val proof_SYM : proof -> proof
    val proof_GEN : proof -> term -> proof
    val proof_DISJ1 : proof -> term -> proof
    val proof_DISJ2 : proof -> term -> proof
    val proof_NOTI : proof -> proof
    val proof_NOTE : proof -> proof
    val proof_CONTR : proof -> term -> proof
    val proof_DISJCASES : proof -> proof -> proof -> proof
    val proof_CHOOSE : term -> proof -> proof -> proof
    val proof_EXISTS : term -> term -> proof -> proof

    val new_axiom_name : string -> string
    val proof_new_axiom : string -> term -> proof

    val save_proof : string -> proof -> (term option) -> unit
    val proof_database : unit -> ((string * proof * (term option)) list)

    val export_saved_proofs : unit -> unit
    val export_one_proof : string -> unit
    val export_list : string list -> unit
  end;;


module Proofobjects : Proofobject_primitives = struct


  let THEORY_NAME = "hollight";;



  (****** Utilities ******)

  (* this is a little bit dangerous, because the function is not injective,
     but I guess one can live with that *)
  let modify = function
    | "/" -> "_slash_"
    | "\\" -> "_backslash_"
    | "=" -> "_equal_"
    | ">" -> "_greaterthan_"
    | "<" -> "_lessthan_"
    | "?" -> "_questionmark_"
    | "!" -> "_exclamationmark_"
    | "*" -> "_star_"
    | "~" -> "_tilde_"
    | "," -> "_comma_"
    | "@" -> "_at_"
    | "+" -> "_plus_"
    | "-" -> "_minus_"
    | "%" -> "_percent_"
    | "$" -> "_dollar_"
    | "." -> "_dot_"
    | "'" -> "_quote_"
    | "|" -> "_pipe_"
    | ":" -> "_colon_"
    | s -> s;;

  let mfc s = implode (map modify (explode s));;

  let ensure_export_directory thyname =
    let dir = Sys.getenv "HOLPROOFEXPORTDIR" in
    let dirsub = Filename.concat dir "hollight" in
    let dirsubsub = Filename.concat dirsub thyname in
    let mk d = if Sys.file_exists d then () else Unix.mkdir d 509
    in mk dir; mk dirsub; mk dirsubsub; dirsubsub;;


  (****** Proofs ******)

  type proof_info_rec =
      {disk_info: (string * string) option ref;
       status: int ref;
       references: int ref;
       queued: bool ref};;

  type proof_info = Info of proof_info_rec;;

  type proof =
    | Proof of (proof_info * proof_content * (unit -> unit))
  and proof_content =
    | Prefl of term
    | Pbeta of string * hol_type * term
    | Pinstt of proof * (string * hol_type) list
    | Pabs of proof * string * hol_type
    | Pdisch of proof * term
    | Phyp of term
    | Pspec of proof * term
    | Pinst of proof * (string * hol_type * term) list
    | Pgen of proof * string * hol_type
    | Psym of proof
    | Ptrans of proof * proof
    | Pcomb of proof * proof
    | Peqmp of proof * proof
    | Pexists of proof * term * term
    | Pchoose of string * hol_type * proof * proof
    | Pconj of proof * proof
    | Pconjunct1 of proof
    | Pconjunct2 of proof
    | Pdisj1 of proof * term
    | Pdisj2 of proof * term
    | Pdisjcases of proof * proof * proof
    | Pnoti of proof
    | Pnote of proof
    | Pcontr of proof * term
    | Pimpas of proof * proof
    | Paxm of string * term
    | Pdef of string * hol_type * term
    | Ptyintro of hol_type * string * hol_type list * string * string * term;;

  let content_of (Proof (_,p,_)) = p;;

  let inc_references (Proof(Info{references=r},_,_) as p) = incr r; p;;

  let mk_proof p = Proof(Info {disk_info = ref None; status = ref 0; references = ref 0; queued = ref false}, p, fun () -> ());;

  let global_ax_counter = let counter = ref 1 in let f = fun () -> (incr counter; !counter - 1) in f;;

  let new_axiom_name n = "ax_"^n^"_"^(string_of_int (global_ax_counter () ));;


  (* corresponds to REFL *)

  let proof_REFL t = mk_proof (Prefl t);;


  (* corresponds to TRANS, with a simple improvment *)

  let proof_TRANS (p,q) =
    match (content_of p, content_of q) with
      (* | (Prefl _,_) -> q *)
      (* | (_, Prefl _) -> p *)
      | _ -> mk_proof (Ptrans (inc_references p, inc_references q));;


  (* corresponds to MK_COMB -> Pcomb *)

  let proof_MK_COMB (p1,p2) =
    match (content_of p1, content_of p2) with
      | (Prefl tm1, Prefl tm2) -> mk_proof (Prefl (mk_comb (tm1, tm2)))
      | _ ->  mk_proof (Pcomb (inc_references p1, inc_references p2));;


  (* corresponds to ASSUME -> Phyp *)

  let proof_ASSUME t = mk_proof (Phyp t);;


  (* corresponds to EQ_MP, with a simple improvment *)

  let proof_EQ_MP p q =
    match content_of p with
      | Prefl _ -> q
      | _ -> mk_proof (Peqmp(inc_references p, inc_references q));;


  (* corresponds to IMP_ANTISYM_RULE th1 th2
     not a base rule
     used only in the extended mode *)

  (*  A1 |- t1 ==> t2     A2 |- t2 ==> t1 *)
  (* ------------------------------------- IMP_ANTISYM_RULE *)
  (*          A1 u A2 |- t1 <=> t2 *)

  let proof_IMPAS p1 p2 = mk_proof (Pimpas (inc_references p1, inc_references p2));;


  (* corresponds to DISCH
     not a base rule
     used only in the extended mode *)

  (*        A |- t *)
  (* -------------------- DISCH `u` *)
  (*  A - {u} |- u ==> t *)

  let proof_DISCH p t = mk_proof (Pdisch(inc_references p, t));;


  (* corresponds to DEDUCT_ANTISYM_RULE *)
  (* made with IMPAS and DISCH (whereas in HOL-Light IMPAS is made with DAR and UNDISCH...) *)

  (*       A |- p       B |- q *)
  (* ---------------------------------- *)
  (*  (A - {q}) u (B - {p}) |- p <=> q *)

  let proof_DEDUCT_ANTISYM_RULE (p1,t1) (p2,t2) =
    proof_IMPAS (proof_DISCH p2 t1) (proof_DISCH p1 t2);;


  (* BETA is a base rule *)

  let proof_BETA tm =
    try
      let f,_ = dest_comb tm in
      let v,bod = dest_abs f in
      let (x, ty) = dest_var v in
      mk_proof (Pbeta (x, ty, bod))
    with
      | _ -> failwith "proof_BETA"


  (* corresponds to ABS, with a simple improvment *)

  let proof_ABS x p =
    match x with
      | Var(s, ty) ->
          mk_proof (Pabs(inc_references p, s, ty))
      | _ -> failwith "proof_ABS: not a variable";;


  (* corresponds to INST_TYPE -> Pinstt *)

  let proof_INST_TYPE s p =
    mk_proof (Pinstt(inc_references p, List.map (
                       fun (ty1, ty2) -> match ty2 with
                         | Tyvar s -> (s, ty1)
                         | _ -> failwith "proof_INST_TYPE: some redex is not a type variable"
                     ) s));;


  (* corresponds to INST *)

  let proof_INST s p =
    mk_proof (Pinst(inc_references p, List.map (
                      fun (t1, t2) -> match t2 with
                        | Var(s, ty) ->
                            (s, ty, t1)
                        | _ -> failwith "proof_INST: some redex is not a term variable"
                    ) s));;


  (* proof_new_definition is called in Thm.new_basic_definition. This
     latter helps to define basic concepts such as T, AND... (almost
     everything in Bool)... and to define derived rules!! -> Pdef *)

  let proof_new_definition cname ty t =
    mk_proof (Pdef (cname, ty, t));;


  (* proof_new_axiom is called in Thm.new_axiom. This latter transforms
     a term of type bool into a theorem. The main three axioms are
     ETA_AX, SELECT_AX and INFINITY_AX. The other axiom is ax (in
     drule.ml) -> Paxm *)

  let proof_new_axiom axname t = mk_proof (Paxm (axname, t));;


  (* corresponds to CONJ
     not a base rule
     used only in the extended mode *)

  let proof_CONJ p1 p2 = mk_proof (Pconj (inc_references p1, inc_references p2));;


  (* corresponds to CONJUNCT1
     not a base rule
     used only in the extended mode
     also used in Thm.new_basic_definition *)

  let proof_CONJUNCT1 p = mk_proof (Pconjunct1 (inc_references p));;


  (* corresponds to CONJUNCT2
     not a base rule
     used only in the extended mode
     also used in Thm.new_basic_definition *)

  let proof_CONJUNCT2 p = mk_proof (Pconjunct2 (inc_references p));;


  (* used only in Thm.new_basic_definition for the same purpose as for
     CONJUNCTi -> Ptyintro *)

  let proof_new_basic_type_definition tyname (absname, repname) (pt,tt) _ =
    let rty = type_of tt in
    let tyvars = sort (<=) (type_vars_in_term pt) in

    mk_proof(Ptyintro(rty, tyname, tyvars, absname, repname, pt));;


  (* ---- used only in substitute_proof calls ---- *)

  (* corresponds to Bool.SPEC, the !-elimination rule *)

  let proof_SPEC s p = mk_proof (Pspec(inc_references p, s));;


  (* corresponds to Equal.SYM, the symmetry rule *)

  let proof_SYM p = mk_proof (Psym(inc_references p));;


  (* corresponds to Bool.GEN, the !-introduction rule *)

  let proof_GEN p a =
    match a with
      | Var(s, ty) ->
          mk_proof (Pgen(inc_references p, s, ty))
      | _ -> failwith "proof_GEN: not a term variable";;


  (* corresponds to Bool.DISJ1, the \/-left introduction rule *)

  let proof_DISJ1 p a = mk_proof (Pdisj1 (inc_references p, a));;


  (* corresponds to Bool.DISJ2, the \/-right introduction rule *)

  let proof_DISJ2 p a = mk_proof (Pdisj2 (inc_references p, a));;


  (* corresponds to Bool.NOT_INTRO, the following rule: *)
  (*     A |- t ==> F *)
  (*    --------------  NOT_INTRO *)
  (*       A |- ~t *)

  let proof_NOTI p = mk_proof (Pnoti (inc_references p));;


  (* corresponds to Bool.NOT_ELIM, the following rule: *)
  (*       A |- ~t *)
  (*    --------------  NOT_ELIM *)
  (*     A |- t ==> F *)

  let proof_NOTE p = mk_proof (Pnote (inc_references p));;


  (* corresponds to Bool.CONTR, the intuitionistic F-elimination rule: *)
  (*     A |- F *)
  (*    --------  CONTR `t` *)
  (*     A |- t *)

  let proof_CONTR p a = mk_proof (Pcontr (inc_references p, a));;


  (* corresponds to Bool.DISJ_CASES, the \/-elimination rule: *)
  (*     A |- t1 \/ t2     A1 u {t1} |- t      A2 u {t2} |- t *)
  (*    ------------------------------------------------------  DISJ_CASES *)
  (*                     A u A1 u A2 |- t *)

  let proof_DISJCASES p q r =
    mk_proof (Pdisjcases (inc_references p, inc_references q, inc_references r));;


  (* corresponds to Bool.CHOOSE, the ?-elimination rule: *)
  (*     A1 |- ?x. s[x]    A2 |- t *)
  (*    -------------------------------  CHOOSE (`v`,(A1 |- ?x. s)) *)
  (*      A1 u (A2 - {s[v/x]}) |- t *)
  (* Where v is not free in A2 - {s[v/x]} or t. *)

  let proof_CHOOSE a p q =
    let (x,ty) = dest_var a in
    mk_proof (Pchoose (x, ty, inc_references p, inc_references q));;


  (* corresponds to Bool.EXISTS, the ?-introduction rule: *)
  (*     A |- p[u/x] *)
  (*    -------------  EXISTS (`?x. p`,`u`) *)
  (*     A |- ?x. p *)
  (* x is p, y is u *)

  let proof_EXISTS etm y p  =
    let _,x = dest_comb etm in
    mk_proof (Pexists (inc_references p, x, y));;


  (****** Utilities for exportation ******)

  let content_of (Proof (_,x,_)) = x;;


  let disk_info_of (Proof(Info {disk_info=di},_,_)) = !di;;


  let set_disk_info_of (Proof(Info {disk_info=di},_,_)) thyname thmname =
    di := Some (thyname,thmname);;

  let reset_disk_info_of1 ((Proof(Info {disk_info=di}, _, _)) as p) =
    di := None; p;;
  let reset_disk_info_of2 (Proof(Info {disk_info=di}, _, _)) =
    di := None;;


  let references (Proof (Info info,_,_)) = !(info.references);;


  let glob_counter = ref 0;;


  let get_counter () = incr glob_counter; !glob_counter;;


  let get_iname = string_of_int o get_counter;;


  let next_counter () = !glob_counter;;


  let trivial p =
    match (content_of p) with
      | Prefl _ -> true
      | Pbeta _ -> true
      | Paxm _ -> true
      | Phyp _ -> true
      | _ -> false;;


  let do_share p = references p > 1 & not (trivial p);;


  (* New expression of terms *)

  let  idT = Hashtbl.create 17
  let defT = Hashtbl.create 17

  let  idT_ref = ref 1
  let defT_ref = ref 1

  let make_idT x =
    try Hashtbl.find idT x with | Not_found -> let n = !idT_ref in incr idT_ref; Hashtbl.add idT x n; n

  let make_defT x =
    try Hashtbl.find defT x with | Not_found -> let n = !defT_ref in incr defT_ref; Hashtbl.add defT x n; n


  type ntype =
    | Ntvar of int
    | Nbool
    | Narrow of ntype * ntype
    | Ntdef of int * ntype list


  let rec hol_type2ntype = function
    | Tyvar x -> Ntvar (make_idT x)
    | Tyapp (s, _) when s = "bool" -> Nbool
    | Tyapp (s, l) when s = "fun" ->
        (match l with
           | [a;b] -> Narrow (hol_type2ntype a, hol_type2ntype b)
           | _ -> failwith "hol_type2ntype: wrong number of arguments for fun")
    | Tyapp (s, l) -> Ntdef (make_defT s, List.map hol_type2ntype l)


  let  idV = Hashtbl.create 17
  let defV = Hashtbl.create 17

  let  idV_ref = ref 1
  let defV_ref = ref 1

  let make_idV x X =
    try
      fst (Hashtbl.find idV x)
    with | Not_found ->
      let n = !idV_ref in incr idV_ref; Hashtbl.add idV x (n,X); n

  let make_defV x X =
    try let (a,_) = (Hashtbl.find defV x) in a with | Not_found -> let n = !defV_ref in incr defV_ref; Hashtbl.add defV x (n,X); n

  let new_name =
    let term_names = ref (-1) in
    fun () ->
      incr term_names;
      "y"^(string_of_int !term_names)


  type ncst =
    | Heq of ntype
    | Heps of ntype
    | Hand
    | Hor
    | Hnot
    | Himp
    | Htrue
    | Hfalse
    | Hforall of ntype
    | Hexists of ntype


  let type_of_ncst = function
    | Heq ty -> Narrow (ty, Narrow (ty, Nbool))
    | Heps ty -> Narrow (Narrow (ty, Nbool), ty)
    | Hand -> Narrow (Nbool, Narrow (Nbool, Nbool))
    | Hor -> Narrow (Nbool, Narrow (Nbool, Nbool))
    | Hnot -> Narrow (Nbool, Nbool)
    | Himp -> Narrow (Nbool, Narrow (Nbool, Nbool))
    | Htrue -> Nbool
    | Hfalse -> Nbool
    | Hforall ty -> Narrow (Narrow (ty, Nbool), Nbool)
    | Hexists ty -> Narrow (Narrow (ty, Nbool), Nbool)


  type nterm =
    | Nvar of int * ntype
    | Ncst of ncst
    | Ndef of int * ntype
    | Napp of nterm * nterm
    | Nabs of int * ntype * nterm


  let rec term2nterm = function
    | Var (x, ty) ->
        let typ = hol_type2ntype ty in
        Nvar (make_idV x typ, typ)
    | Comb (t1, t2) -> Napp (term2nterm t1, term2nterm t2)
    | Abs (t1, t2) ->
        (match t1 with
           | Var (x, ty) ->
               let typ = hol_type2ntype ty in
               let n = make_idV x typ in
               Nabs (n, typ, term2nterm t2)
           | _ -> failwith "term2nterm: first argument of an abstraction is not a variable")
    | Const (s, ty) when s = "=" ->
        (match hol_type2ntype ty with
           | Narrow(a, _) -> Ncst (Heq a)
           | _ -> failwith "term2nterm: constant = must have arrow type")
    | Const (s, ty) when s = "@" ->
        (match hol_type2ntype ty with
           | Narrow(_, a) -> Ncst (Heps a)
           | _ -> failwith "term2nterm: constant @ must have arrow type")
    | Const (s, ty) when s = "/\\" -> Ncst Hand
    | Const (s, ty) when s = "\\/" -> Ncst Hor
    | Const (s, ty) when s = "~" -> Ncst Hnot
    | Const (s, ty) when s = "==>" -> Ncst Himp
    | Const (s, ty) when s = "T" -> Ncst Htrue
    | Const (s, ty) when s = "F" -> Ncst Hfalse
    | Const (s, ty) when s = "_FALSITY_" -> Ncst Hfalse
    | Const (s, ty) when s = "!" ->
        (match hol_type2ntype ty with
           | Narrow(Narrow (a, _), _) -> Ncst (Hforall a)
           | _ -> failwith "term2nterm: constant ! must have arrow type")
    | Const (s, ty) when s = "?" ->
        (match hol_type2ntype ty with
           | Narrow(Narrow (a, _), _) -> Ncst (Hexists a)
           | _ -> failwith "term2nterm: constant ? must have arrow type")
    | Const (s, ty) ->
        let typ = hol_type2ntype ty in
        Ndef(make_defV s typ, typ)


  (* let rec type_of = function *)
  (*   | Nvar (_, ty) -> ty *)
  (*   | Ncst c -> type_of_ncst c *)
  (*   | Ndef (_, ty) -> ty *)
  (*   | Napp (u, v) -> *)
  (*       (match type_of u with *)
  (*          | Narrow (_, a) -> a *)
  (*          | _ -> failwith "type_of: ill-typed application") *)
  (*   | Nabs (_, ty, u) -> Narrow (ty, type_of u) *)


  let type_of t =

    let rec type_of k = function
      | Nvar (_, ty) -> k ty
      | Ncst c -> k (type_of_ncst c)
      | Ndef (_, ty) -> k ty
      | Napp (u, v) ->
          type_of (fun r -> match r with
                     | Narrow (_, a) -> k a
                     | _ -> failwith "type_of: ill-typed application") u
      | Nabs (_, ty, u) -> type_of (fun r -> k (Narrow (ty, r))) u in

  type_of (fun x -> x) t


  let hforall x ty t = Napp (Ncst (Hforall ty), Nabs (x, ty, t))
  let heq ty u v = Napp (Napp (Ncst (Heq ty), u), v)
  let himp u v = Napp (Napp (Ncst Himp, u), v)
  let hequiv u v = Napp (Napp (Ncst (Heq Nbool), u), v)


  (* Functions on sorted unredundant lists *)

  let rec insert a = function
    | [] -> [a]
    | t::q ->
        let i = Pervasives.compare a t in
        if i = 0 then
          t::q
        else if i < 0 then
          a::t::q
        else
          t::(insert a q)


  let rec remove a = function
    | [] -> []
    | t::q ->
        let i = Pervasives.compare a t in
        if i = 0 then
          q
        else if i < 0 then
          t::q
        else
          t::(remove a q)


  let fusion l1 l2 =
    if List.length l1 > List.length l2 then
      List.fold_left (fun res a -> insert a res) l1 l2
    else
      List.fold_left (fun res a -> insert a res) l2 l1


  (* Free variables (both of types and terms) of a term *)

  let fv =

    let rec fV = function
      | Ntvar i -> [i]
      | Narrow (u,v) -> fusion (fV u) (fV v)
      | Ntdef (_,l) -> List.fold_left (fun res e -> fusion (fV e) res) [] l
      | _ -> [] in

    let fvcst = function
      | Heq ty | Heps ty | Hforall ty | Hexists ty -> fV ty
      | _ -> [] in

    let rec fv = function
      | Nvar (i, ty) -> [(i, ty)], fV ty
      | Ncst c -> [], fvcst c
      | Ndef (_,ty) -> [], fV ty
      | Napp (u, v) ->
        let fvu, fVu = fv u in
        let fvv, fVv = fv v in
        fusion (fvu) (fvv), fusion fVu fVv
      | Nabs (i, ty, v) ->
        let fvv, fVv = fv v in
        remove (i, ty) (fvv), fusion (fV ty) fVv in

    (* let rec fv k = function *)
    (*   | Nvar (i, ty) -> k [(i, ty)] *)
    (*   | Ncst _ -> k [] *)
    (*   | Ndef _ -> k [] *)
    (*   | Napp (u, v) -> fv (fun r1 -> fv (fun r2 -> k (fusion r1 r2)) u) v *)
    (*   | Nabs (i, ty, v) -> fv (fun r -> k (remove (i, ty) r)) v in *)

    (* fv (fun x -> x) *)

    fv


  (* Terms closure *)

  let close_term t fvt =
    List.fold_left (fun u (i, ty) -> hforall i ty u) t (List.rev fvt)


  (* Substitutions *)

  let remove_subst_idv x ty l =

    let rec remove_subst_idv x ty acc = function
      | [] -> acc
      | ((i, typ, _) as t)::q ->
          if x = i && ty = typ then
            remove_subst_idv x ty acc q
          else
            remove_subst_idv x ty (t::acc) q in

    remove_subst_idv x ty [] l


  let rec subst_idv_aux i typ = function
    | [] -> Nvar (i, typ)
    | (n, ty, u)::q -> if i = n && typ = ty then u else
        subst_idv_aux i typ q


  (* let rec subst_idv t l = *)
  (*   match t with *)
  (*     | Nvar (i, typ) -> subst_idv_aux i typ l *)
  (*     | Napp (u, v) -> Napp (subst_idv u l, subst_idv v l) *)
  (*     | Nabs (x, ty, u) -> *)
  (*         Nabs (x, ty, subst_idv u (remove_subst_idv x ty l)) *)
  (*     | t -> t *)

  let subst_idv t l =

    let rec subst_idv t l k =
      match t with
        | Nvar (i, typ) -> k (subst_idv_aux i typ l)
        | Napp (u, v) -> subst_idv u l (fun r -> subst_idv v l (fun r' -> k (Napp (r, r'))))
        | Nabs (x, ty, u) -> subst_idv u (remove_subst_idv x ty l) (fun r -> k (Nabs (x, ty, r)))
        | t -> k t in

    subst_idv t l (fun x -> x)


  let rec subst_idt_aux v = function
    | [] -> Ntvar v
    | (n, ty)::q -> if v = n then ty else subst_idt_aux v q

  let rec subst_idt_type l = function
    | Ntvar i -> subst_idt_aux i l
    | Narrow (a,b) -> Narrow (subst_idt_type l a, subst_idt_type l b)
    | Ntdef (i, l') -> Ntdef (i, List.map (subst_idt_type l) l')
    | ty -> ty

  let subst_idt_cst l = function
    | Heq ty -> Heq (subst_idt_type l ty)
    | Heps ty -> Heps (subst_idt_type l ty)
    | Hforall ty -> Hforall (subst_idt_type l ty)
    | Hexists ty -> Hexists (subst_idt_type l ty)
    | c -> c

  let subst_idt t l =

    let rec subst_idt = function
      | Nvar (i, ty) -> Nvar (i, subst_idt_type l ty)
      | Ncst c -> Ncst (subst_idt_cst l c)
      | Ndef (i, ty) -> Ndef (i, subst_idt_type l ty)
      | Napp (u,v) -> Napp (subst_idt u, subst_idt v)
      | Nabs (i, ty, t) -> Nabs (i, subst_idt_type l ty, subst_idt t) in

    subst_idt t


  (* New expression of proofs *)

  type nproof =
    | Nprefl of nterm * ntype
    | Nptrans of nproof * nproof * ntype * nterm * nterm * nterm
    | Npabs of ntype * ntype * int * nterm * nterm * string * (((int * ntype) list) * (int list)) * nterm list
    | Npbeta of ntype * ntype * int * nterm * nterm
    | Npinst of string * (((int * ntype) list) * (int list)) * (int * ntype * nterm) list * nterm list
    | Npinstt of string * (((int * ntype) list) * (int list)) * (int * ntype) list * nterm list
    | Npcomb of ntype * ntype * nterm * nterm * nterm * nterm * nproof * nproof
    | Nphyp of nterm
    | Npdisch of string * (((int * ntype) list) * (int list)) * nterm * int * nterm list
    | Npimpas of nterm * nterm * nproof * nproof
    | Npeqmp of nterm * nterm * nproof * nproof
    | Nfact of string * (((int * ntype) list) * (int list))


  (* Equality for types and terms *)

  let rec eq_type t1 t2 =
    match t1, t2 with
      | Ntvar i, Ntvar j -> i = j
      | Nbool, Nbool -> true
      | Narrow (a,b), Narrow (c,d) -> (eq_type a c) && (eq_type b d)
      | Ntdef (i,l), Ntdef (j,m) -> (i = j) && (compare_list l m)
      | _, _ -> false

  and compare_list l m =
    match l, m with
      | [], [] -> true
      | t::q, u::r -> (eq_type t u) && (compare_list q r)
      | _, _ -> false

  let eq_cst c d =
    match c, d with
      | Heq t1, Heq t2 | Heps t1, Heps t2 | Hforall t1, Hforall t2 | Hexists t1, Hexists t2 -> eq_type t1 t2
      | Hand, Hand | Hor, Hor | Hnot, Hnot | Himp, Himp | Htrue, Htrue | Hfalse, Hfalse -> true
      | _, _ -> false

  let eq_term t1 t2 =

    let rec ext_var i t1 l1 j t2 l2 =
      match l1, l2 with
        | [], [] -> i = j
        | (x,ty1)::xs, (y,ty2)::ys ->
          if ((x = i) && eq_type ty1 t1) then (
            (y = j) && (eq_type ty2 t2)
          ) else (
            ((y <> j) or not (eq_type ty2 t2)) && (ext_var i t1 xs j t2 ys)
          )
        | _, _ -> false in

    let rec eq_term l1 l2 t1 t2 =
      match t1, t2 with
        | Nvar (i,t1), Nvar (j,t2) -> (eq_type t1 t2) && (ext_var i t1 l1 j t2 l2)
        | Ncst c, Ncst d -> eq_cst c d
        | Ndef (i,t1), Ndef (j,t2) -> (i = j) && (eq_type t1 t2)
        | Napp (u1,v1), Napp (u2,v2) -> (eq_term l1 l2 u1 u2) && (eq_term l1 l2 v1 v2)
        | Nabs (i,t1,u), Nabs (j,t2,v) -> (eq_type t1 t2) && (eq_term ((i,t1)::l1) ((j,t2)::l2) u v)
      | _, _ -> false in

    eq_term [] [] t1 t2


  (* Pretty printers *)

  let rec print_type out = function
    | Ntvar i -> out "X"; out (string_of_int i)
    | Nbool -> out "hol.o"
    | Narrow (a,b) -> out "(hol.arrow "; print_type out a; out " "; print_type out b; out ")"
    | Ntdef (i,l) -> failwith "print_type: Ntdef not implemented yet"


  let print_cst out = function
    | Heq ty -> out "(hol.Eq "; print_type out ty; out ")"
    | Heps _ -> failwith "print_cst: epsilon not implemented yet"
    | Hand -> out "hol.And"
    | Hor  -> out "hol.Or"
    | Hnot -> out "hol.Not"
    | Himp -> out "hol.Imp"
    | Htrue -> out "hol.True"
    | Hfalse -> out "hol.False"
    | Hforall ty -> out "(hol.Forall "; print_type out ty; out ")"
    | Hexists ty -> out "(hol.Exists "; print_type out ty; out ")"


  let rec print_term out = function
    | Nvar (i, _) -> out "x"; out (string_of_int i)
    | Ncst c -> print_cst out c
    | Ndef _ -> failwith "print_term: definitions not implemented yet"
    | Napp (u, v) ->
        (match type_of u with
           | Narrow (a, b) ->
               out "(hol.App "; print_type out a; out " "; print_type out b;
               out " "; print_term out u; out " "; print_term out v; out ")"
           | _ -> failwith "print_term: wrong type in application")
    | Nabs (i, ty, u) ->
        out "(hol.Lam "; print_type out ty; out " ";
        print_type out (type_of u); out " (x"; out (string_of_int i);
        out ": hol.hterm "; print_type out ty; out " => "; print_term out u;
        out "))"


  let print_proof out hyps p =

    let rec print_proof = function
      | Nprefl (t, ty) ->
        out "(hol.refl "; print_type out ty; out " "; print_term out t; out ")"
      | Nptrans (p1, p2, ty, u, v, w) ->
        out "(hol.trans "; print_type out ty; out " "; print_term out u; out " "; print_term out v; out " "; print_term out w; out " "; print_proof p1; out " "; print_proof p2; out ")"
      | Npabs (typ, ty1, n, u, v, name, fvall, h) ->
        let (fvt, fVt) = fvall in
        out "(hol.fun_ext "; print_type out typ; out " "; print_type out ty1; out " "; print_term out (Nabs (n, typ, u)); out " "; print_term out (Nabs (n, typ, v)); out " "; out "(x"; out (string_of_int n); out ": hol.hterm "; print_type out typ; out " => "; out name; List.iter (fun i -> out " X"; out (string_of_int i)) fVt; List.iter (fun (x, _) -> out " x"; out (string_of_int x)) fvt; List.iter (fun (_, n) -> out " "; out n) (List.filter (fun (t,_) -> List.mem t h) hyps); out "))"
      | Npbeta (a, b, n, t, u) ->
        out "(hol.beta "; print_type out a; out " "; print_type out b; out " (x"; out (string_of_int n); out ": hol.hterm "; print_type out a; out " => "; print_term out t; out ") "; print_term out u; out ")"
      | Npinst (name, fvall, l', h) ->
        let (fvt, fVt) = fvall in
        out "("; out name; List.iter (fun i ->
          out " X"; out (string_of_int i)) fVt; List.iter (fun (i, ty) ->
            let t = subst_idv_aux i ty l' in
            out " "; print_term out t) fvt; List.iter (fun (_, n) -> out " "; out n) ((* List.filter (fun (t,_) -> List.mem t h) *) hyps); out ")"
      | Npinstt (name, fvall, l', h) ->
        let (fvt, fVt) = fvall in
        out "("; out name; List.iter (fun i ->
          let t = subst_idt_aux i l' in
          out " "; print_type out t) fVt; List.iter (fun (i, _) ->
            out " x"; out (string_of_int i)) fvt; List.iter (fun (_, n) -> out " "; out n) ((* List.filter (fun (t,_) -> List.mem t h) *) hyps); out ")"
      | Npcomb (a, b, s, t, u, v, p'1, p'2) ->
        out "(hol.mk_comb "; print_type out a; out " "; print_type out b; out " "; print_term out s; out " "; print_term out t; out " "; print_term out u; out " "; print_term out v; out " "; print_proof p'1; out " "; print_proof p'2; out ")"
      | Nphyp t -> out (List.assoc t hyps)
      | Npdisch (name, fvall, t, pl, h) ->
        let (fvt, fVt) = fvall in
        let hyps' = List.filter (fun (t,_) -> List.mem t h) hyps in
        out "("; let s = new_name () in out s; out ": hol.eps "; print_term out t; out " => "; out name; List.iter (fun i -> out " X"; out (string_of_int i)) fVt; List.iter (fun (x, _) -> out " x"; out (string_of_int x)) fvt; if (List.length hyps' = 0 && pl = 0) then (out " "; out s) else (let i = ref 0 in List.iter (fun (_, n) -> if !i = pl then (out " "; out s); out " "; out n; incr i) hyps'); out ")"
      | Npimpas (p, q, p1, p2) ->
        out "(hol.prop_ext "; print_term out p; out " "; print_term out q; out " "; print_proof p1; out " "; print_proof p2; out ")"
      | Npeqmp (p, q, p1, p2) ->
        out "(hol.eq_mp "; print_term out p; out " "; print_term out q; out " "; print_proof p1; out " "; print_proof p2; out ")"
      | Nfact (thm, fvall) ->
        let (fvt, fVt) = fvall in
        out "("; out thm; List.iter (fun i -> out " X"; out (string_of_int i)) fVt; List.iter (fun (x, _) -> out " x"; out (string_of_int x)) fvt; out ")" in

    print_proof p


  (* Pretty printer for the old proof format (for debugging) *)

  let rec pp_proof out p =
    pp_proof2 out (content_of p)

  and pp_proof2 out = function
    | Prefl t -> out "(Prefl "; print_term out (term2nterm t); out ")"
    | Pbeta (s, ty, t) -> out "(Pbeta "; out s; out ", "; print_type out (hol_type2ntype ty); out ", "; print_term out (term2nterm t); out ")"
    | Pinstt (p, l) -> out "(Pinstt "; pp_proof out p; out ", [";
      (match l with
        | [] -> ()
        | (s,ty)::q -> out "("; out s; out ", "; print_type out (hol_type2ntype ty); out ")"; List.iter (fun (s,ty) -> out "; ("; out s; out ", "; print_type out (hol_type2ntype ty); out ")") q);
      out "])"
    | Pabs (p, s, ty) -> out "(Pabs "; pp_proof out p; out ", "; out s; out ", "; print_type out (hol_type2ntype ty); out ")"
    | Pdisch (p,t) -> out "(Pdisch "; pp_proof out p; out ", "; print_term out (term2nterm t); out ")"
    | Phyp t -> out "(Phyp "; print_term out (term2nterm t); out ")"
    | Pinst (p, l) -> out "(Pinst "; pp_proof out p; out ", [";
      (match l with
        | [] -> ()
        | (s,ty,t)::q ->
          let typ = hol_type2ntype ty in
          out "(x"; out (string_of_int (make_idV s typ)); out ", "; print_type out typ; out ", "; print_term out (term2nterm t); out ")"; List.iter (fun (s,ty,t) ->
            let typ = hol_type2ntype ty in
            out "; (x"; out (string_of_int (make_idV s typ)); out ", "; print_type out typ; out ", "; print_term out (term2nterm t); out ")") q);
      out "])"
    | Ptrans (p1,p2) -> out "(Ptrans "; pp_proof out p1; out ", "; pp_proof out p2; out ")"
    | Pcomb (p1,p2) -> out "(Pcomb "; pp_proof out p1; out ", "; pp_proof out p2; out ")"
    | Peqmp (p1,p2) -> out "(Peqmp "; pp_proof out p1; out ", "; pp_proof out p2; out ")"
    | Pimpas (p1,p2) -> out "(Pimpas "; pp_proof out p1; out ", "; pp_proof out p2; out ")"
    | Pspec _ -> out "Pspec"
    | Pgen _ -> out "Pgen"
    | Psym _ -> out "Psym"
    | Pexists _ -> out "Pexists"
    | Pchoose _ -> out "Pchoose"
    | Pconj _ -> out "Pconj"
    | Pconjunct1 _ -> out "Pconjunct1"
    | Pconjunct2 _ -> out "Pconjunct2"
    | Pdisj1 _ -> out "Pdisj1"
    | Pdisj2 _ -> out "Pdisj2"
    | Pdisjcases _ -> out "Pdisjcases"
    | Pnoti _ -> out "Pnoti"
    | Pnote _ -> out "Pnote"
    | Pcontr _ -> out "Pcontr"
    | Paxm _ -> out "Paxm"
    | Pdef (s,ty,t) -> out "(Pdef "; out s; out ", "; print_type out (hol_type2ntype ty); out ", "; print_term out (term2nterm t); out ")"
    | Ptyintro _ -> out "Ptyintro"

  (* Facilities *)

  let heq a t u = Napp (Napp (Ncst (Heq a), t), u);;
  let hequiv t u = Napp (Napp (Ncst (Heq Nbool), t), u);;
  let himp t u = Napp (Napp (Ncst Himp, t), u);;
  let hand t u = Napp (Napp (Ncst Hand, t), u);;
  let hor t u = Napp (Napp (Ncst Hor, t), u);;
  let hnot t = Napp (Ncst Hnot, t);;
  let htrue = Ncst Htrue;;
  let hfalse = Ncst Hfalse;;
  let hforall x a p = Napp (Ncst (Hforall a), Nabs (x, a, p));;
  let hexists x a p = Napp (Ncst (Hexists a), Nabs (x, a, p));;


  (* Contexts : sets of nterms *)

  module Nterm : Set.OrderedType with type t = nterm = struct
    type t = nterm
    let compare = Pervasives.compare
  end

  module Context = struct
    include Set.Make(Nterm)
    let map f s = fold (fun e res -> add (f e) res) s empty
    let place e s =
      let rec place i = function
        | [] -> raise Not_found
        | a::_ when Nterm.compare a e = 0 -> i
        | _::q -> place (i+1) q in
      place 0 (elements s)
  end


  (* Dealing with dependencies *)

  let total = ref 0


  let (* rec *) make_dependencies_aux dep_graph proof_of_thm (thmname, p, c_opt) = (* function *)
    (* | [] -> () *)
    (* | (thmname, p, c_opt)::il -> *)

  let wdi thm fvall =
    Depgraph.Dep.add_dep dep_graph thm thmname;
    Nfact (thm, fvall) in

  let share_info_of p = (* None in *)
      (* match content_of p with *)
      (*   | Pabs (p, _, _) -> *)
      (*       let name = THEORY_NAME^"_"^(get_iname ()) in *)
      (*       set_disk_info_of p THEORY_NAME name; *)
      (*       Depgraph.Dep.add_thm dep_graph name; *)
      (*       Some(THEORY_NAME,name,(name,p,None)) *)
      (*   | _ -> None *)
    match (disk_info_of p) with
      | Some (thyname,thmname2) ->
        Some(thyname,thmname2,None(* ,il *))
      | None ->
        if do_share p then (
          let name = THEORY_NAME^"_"^(get_iname ()) in
          set_disk_info_of p THEORY_NAME name;
          Depgraph.Dep.add_thm dep_graph name;
          Some(THEORY_NAME,name,Some p(* (name,p,None)::il *))
        ) else (
          None
        ) in

  let rec write_proof p =

    incr total;
    wp' (content_of p)

  and wp' = function
    | Prefl t ->
      (* print_string "Prefl\n"; *)
      let u = term2nterm t in
      let ty = type_of u in
      (Nprefl (u, ty), Context.empty, heq ty u u)

    | Ptrans (p1,p2) ->
      (* print_string "Ptrans\n"; *)
      let p'1, h1, t1 = wp p1 in
      let p'2, h2, t2 = wp p2 in
      (match t1, t2 with
        | Napp (Napp (Ncst (Heq ty), u), v), Napp (Napp (Ncst (Heq _), _), w) -> (Nptrans (p'1, p'2, ty, u, v, w), Context.union h1 h2, heq ty u w)
        | _, _ -> failwith "make_dependencies_aux: wp': rule trans incorrect")

    | Pabs (p,x,ty) ->
      (* print_string "Pabs\n"; *)
      let name = THEORY_NAME^"_"^(get_iname ()) in
      set_disk_info_of p THEORY_NAME name;
      Depgraph.Dep.add_thm dep_graph name;
      Depgraph.Dep.add_dep dep_graph name thmname;
      let (p', h, t) = write_proof p in
      Hashtbl.add proof_of_thm name (p', h, t);
      (match t with
        | Napp (Napp (Ncst (Heq ty1), u), v) ->
          let fvt = fv t in
          let fvall = Context.fold (fun t' (res, rEs) ->
            let (fvt', fVt') = fv t' in
            (fusion fvt' res, fusion fVt' rEs)) h fvt in
          let typ = hol_type2ntype ty in
          let n = make_idV x typ in
          (Npabs (typ, ty1, n, u, v, name, (* fvt *) fvall, Context.elements h), h, heq (Narrow (typ, ty1)) (Nabs (n, typ, u)) (Nabs (n, typ, v)))
        | _ -> failwith "make_dependencies_aux: wp': rule abs incorrect")

    | Pbeta (x, ty, t) ->
      (* print_string "Pbeta\n"; *)
      let typ = hol_type2ntype ty in
      let n = make_idV x typ in
      let t' = term2nterm t in
      let ty2 = type_of t' in
      let t2 = Nabs (n, typ, t') in
      let t3 = Nvar (n, typ) in
      (Npbeta (typ, ty2, n, t', t3), Context.empty, heq ty2 (Napp (t2, t3)) t')

    | Pinst (p, l) ->
      (* print_string "Pinst\n"; *)
      let name = THEORY_NAME^"_"^(get_iname ()) in
      set_disk_info_of p THEORY_NAME name;
      Depgraph.Dep.add_thm dep_graph name;
      Depgraph.Dep.add_dep dep_graph name thmname;
      let (p', h, t) = write_proof p in
      Hashtbl.add proof_of_thm name (p', h, t);
      let fvt = fv t in
      let fvall = Context.fold (fun t' (res, rEs) ->
        let (fvt', fVt') = fv t' in
        (fusion fvt' res, fusion fVt' rEs)) h fvt in
      (* let fvall = Context.fold (fun t' res -> fusion (fv t') res) h fvt in *)
      let l' = List.map (fun (s, ty, t) ->
        let typ = hol_type2ntype ty in
        let t' = term2nterm t in
        (make_idV s typ, typ, t')) l in
      (Npinst (name, (* fvt *) fvall, l', Context.elements h), Context.map (fun t2 -> subst_idv t2 l') h, subst_idv t l')

    | Pinstt (p, l) ->
      (* print_string "Pinstt\n"; *)
      let name = THEORY_NAME^"_"^(get_iname ()) in
      set_disk_info_of p THEORY_NAME name;
      Depgraph.Dep.add_thm dep_graph name;
      Depgraph.Dep.add_dep dep_graph name thmname;
      let (p', h, t) = write_proof p in
      Hashtbl.add proof_of_thm name (p', h, t);
      let fvt = fv t in
      let fvall = Context.fold (fun t' (res, rEs) ->
        let (fvt', fVt') = fv t' in
        (fusion fvt' res, fusion fVt' rEs)) h fvt in
      (* let fvall = Context.fold (fun t' res -> fusion (fv t') res) h fvt in *)
      let l' = List.map (fun (s, ty) ->
        let typ = hol_type2ntype ty in
        (make_idT s, typ)) l in
      (Npinstt (name, fvall, l', Context.elements h), Context.map (fun t2 -> subst_idt t2 l') h, subst_idt t l')

    | Pcomb (p1, p2) ->
      (* print_string "Pcomb\n"; *)
      let (p'1, h1, t1) = wp p1 in
      let (p'2, h2, t2) = wp p2 in
      (match (t1, t2) with
        | Napp (Napp (Ncst (Heq (Narrow (a, b))), s), t), Napp (Napp (Ncst (Heq _), u), v) ->
          (Npcomb (a, b, s, t, u, v, p'1, p'2), Context.union h1 h2, heq b (Napp (s, u)) (Napp (t, v)))
        | _ ->
          failwith "make_dependencies_aux: wp': rule comb incorrect")

    | Phyp t ->
      (* print_string "Phyp\n"; *)
      let t' = term2nterm t in
      (Nphyp t', Context.singleton t', t')

    | Pdisch (p, t) ->
      (* print_string "Pdisch\n"; *)
      let name = THEORY_NAME^"_"^(get_iname ()) in
      set_disk_info_of p THEORY_NAME name;
      Depgraph.Dep.add_thm dep_graph name;
      Depgraph.Dep.add_dep dep_graph name thmname;
      let (p', h, t2) = write_proof p in
      Hashtbl.add proof_of_thm name (p', h, t2);
      let fvt = fv t2 in
      let fvall = Context.fold (fun t' (res, rEs) ->
        let (fvt', fVt') = fv t' in
        (fusion fvt' res, fusion fVt' rEs)) h fvt in
      (* let fvall = Context.fold (fun t' res -> fusion (fv t') res) h fvt in *)
      let t' = term2nterm t in
      let pl = try Context.place t' h with | Not_found -> -1 in
      (Npdisch (name, (* fvt *) fvall, t', pl, Context.elements h), Context.remove t' h, himp t' t2)

    | Pimpas (p1, p2) ->
      (* print_string "Pimpas\n"; *)
      let (p'1, h1, t1) = wp p1 in
      let (p'2, h2, t2) = wp p2 in
      (match t1 with
        | Napp (Napp (Ncst Himp, p), q) ->
          (Npimpas (p, q, p'1, p'2), Context.union h1 h2, hequiv p q)
        | _ -> failwith "make_dependencies_aux: wp': rule impas incorrect")

    | Peqmp (p1, p2) ->
      (* print_string "Peqmp\n"; *)
      let (p'1, h1, t1) = wp p1 in
      let (p'2, h2, t2) = wp p2 in
      (match t1 with
        | Napp (Napp (Ncst (Heq Nbool), p), q) ->
          (Npeqmp (p, q, p'1, p'2), Context.union h1 h2, q)
        | _ -> failwith "make_dependencies_aux: wp': rule eq_mp incorrect")

    | Pdef (name, ty, tm) ->
      (* print_string "Pdef\n"; *)
      (match name with
        | "T" ->
          (Nfact ("hol."^THEORY_NAME^"_DEF_T", ([],[])), Context.empty, hequiv htrue (term2nterm tm))
        | "/\\" ->
          let tm = heq (Narrow (Nbool, Narrow (Nbool, Nbool))) (Ncst Hand) (term2nterm tm) in
          (Nfact ("hol."^THEORY_NAME^"_DEF__slash__backslash_", ([],[])), Context.empty, tm)
        | "==>" ->
          let tm = heq (Narrow (Nbool, Narrow (Nbool, Nbool))) (Ncst Himp) (term2nterm tm) in
          (Nfact ("hol."^THEORY_NAME^"_DEF__equal__equal__greaterthan_", ([],[])), Context.empty, tm)
        | "!" ->
          let a2 = hol_type2ntype ty in
          (match a2 with
            | Narrow (Narrow (b, _), _) ->
              let tm = heq a2 (Ncst (Hforall b)) (term2nterm tm) in
              (Nfact ("hol."^THEORY_NAME^"_DEF__exclamationmark_", ([],[])), Context.empty, tm)
            | _ -> failwith "make_dependencies_aux: wp': definition of ! incorrect")
        | "?" ->
          let a2 = hol_type2ntype ty in
          (match a2 with
            | Narrow (Narrow (b, _), _) ->
              let tm = heq a2 (Ncst (Hexists b)) (term2nterm tm) in
              (Nfact ("hol."^THEORY_NAME^"_DEF__questionmark_", ([],[])), Context.empty, tm)
            | _ -> failwith "make_dependencies_aux: wp': definition of ? incorrect")
        | "\\/" ->
          let tm = heq (Narrow (Nbool, Narrow (Nbool, Nbool))) (Ncst Hor) (term2nterm tm) in
          (Nfact ("hol."^THEORY_NAME^"_DEF__backslash__slash_", ([],[])), Context.empty, tm)
        | "F" ->
          let tm = hequiv (Ncst Hfalse) (term2nterm tm) in
          (Nfact ("hol."^THEORY_NAME^"_DEF_F", ([],[])), Context.empty, tm)
        | "~" ->
          let tm = heq (Narrow (Nbool, Nbool)) (Ncst Hnot) (term2nterm tm) in
          (Nfact ("hol."^THEORY_NAME^"_DEF__tilde_", ([],[])), Context.empty, tm)
        | "_FALSITY_" ->
          let tm = heq Nbool (Ncst Hfalse) (Ncst Hfalse) in
          (Nprefl (Ncst Hfalse, Nbool), Context.empty, tm)
        | _ -> failwith "make_dependencies_aux: wp': term definition not implemented yet")

    | _ -> failwith "make_dependencies_aux: wp': rule not implemented yet"


  and wp p =
    match share_info_of p with
      | Some(_, thmname, p_opt) ->
        (match p_opt with
          | Some p ->
            let (p', h, t) = write_proof p in
            Hashtbl.add proof_of_thm thmname (p', h, t);
            let fvt = fv t in
            let fvall = Context.fold (fun t' (res, rEs) ->
              let (fvt', fVt') = fv t' in
              (fusion fvt' res, fusion fVt' rEs)) h fvt in
            wdi thmname fvall, h, t
          | None ->
            let (_, h, t) = Hashtbl.find proof_of_thm thmname in
            let fvt = fv t in
            let fvall = Context.fold (fun t' (res, rEs) ->
              let (fvt', fVt') = fv t' in
              (fusion fvt' res, fusion fVt' rEs)) h fvt in
            wdi thmname fvall, h, t)
      (* | Some(_, thmname, (name, p, c_opt)) -> *)
      (*   let (p', h, t) = write_proof p in *)
      (*   set_disk_info_of p THEORY_NAME thmname; *)
      (*   Hashtbl.add proof_of_thm thmname (p', h, t); *)
      (*   wdi thmname, h, t *)
      | None -> wp' (content_of p) in

          (* match disk_info_of p with *)
          (*   | Some(_, thmname') -> *)
          (*       if thmname' = thmname then *)
          (*         wp' (content_of p) *)
          (*       else *)
          (*         let (a, b) = wdi thmname' in *)
          (*         (a, b, il) *)
          (*   | None -> wp' il (content_of p) in *)

  let (p', h, t) = write_proof p in
  Hashtbl.add proof_of_thm thmname (p', h, t)

        (* let p', t, il = write_proof p il in *)
        (* set_disk_info_of p THEORY_NAME thmname; *)
        (* Hashtbl.add proof_of_thm thmname (p', t); *)
        (* make_dependencies_aux dep_graph proof_of_thm il *)


  (* Export one theorem *)

  let export_thm out thmname hyps cl p =
    let fvcl = fv cl in
    let fvall = Context.fold (fun t' (res, rEs) ->
      let (fvt', fVt') = fv t' in
      (fusion fvt' res, fusion fVt' rEs)) hyps fvcl in
    (* let fvall = Context.fold (fun t res -> fusion (fv t) res) hyps fvcl in *)
    let fvall, fVall = fvall in
    out "\n\n"; out thmname; out " : ";
    List.iter (fun i -> out "X"; out (string_of_int i); out ": hol.htype -> ") fVall;
    out "hol.eps ";
    let t = Context.fold (fun t res -> himp t res) hyps cl in
    print_term out (close_term t (* fvcl *) fvall); out ".\n";
    out "[";
    let ass =
      (match fVall with
        | [] ->
          (match (* fvcl *) fvall with
            | [] ->
              (try
                 let a = Context.min_elt hyps in
                 let n = new_name () in
                 out n; out ": hol.hterm "; print_term out a;
                 Context.fold (fun b acc ->
                   let m = new_name () in
                   out ", "; out m; out ": hol.eps "; print_term out b;
                   (b,m)::acc) (Context.remove a hyps) [(a,n)]
               with | Not_found -> [])
            | (x, ty)::q ->
              out "x"; out (string_of_int x); out ": hol.hterm "; print_type out ty; List.iter (fun (n, typ) -> out ", x"; out (string_of_int n); out ": hol.hterm "; print_type out typ) q;
              Context.fold (fun b acc ->
                let m = new_name () in
                out ", "; out m; out ": hol.eps "; print_term out b;
                (b,m)::acc) hyps [])
        | i::q ->
          out "X"; out (string_of_int i); out ": hol.htype "; List.iter (fun j -> out ", X"; out (string_of_int j); out ": hol.htype") q;
          List.iter (fun (n, typ) -> out ", x"; out (string_of_int n); out ": hol.hterm "; print_type out typ) fvall;
          Context.fold (fun b acc ->
            let m = new_name () in
            out ", "; out m; out ": hol.eps "; print_term out b;
            (b,m)::acc) hyps []) in
    (* let ass = *)
    (*   (match (\* fvcl *\) fvall with *)
    (*     | [] -> *)
    (*       (try *)
    (*          let a = Context.min_elt hyps in *)
    (*          let n = new_name () in *)
    (*          out n; out ": hol.hterm "; print_term out a; *)
    (*          Context.fold (fun b acc -> *)
    (*            let m = new_name () in *)
    (*            out ", "; out m; out ": hol.eps "; print_term out b; *)
    (*            (b,m)::acc) (Context.remove a hyps) [(a,n)] *)
    (*        with | Not_found -> []) *)
    (*     | (x, ty)::q -> *)
    (*       out "x"; out (string_of_int x); out ": hol.hterm "; print_type out ty; List.iter (fun (n, typ) -> out ", x"; out (string_of_int n); out ": hol.hterm "; print_type out typ) q; *)
    (*       Context.fold (fun b acc -> *)
    (*         let m = new_name () in *)
    (*         out ", "; out m; out ": hol.eps "; print_term out b; *)
    (*         (b,m)::acc) hyps []) in *)
    out "] ";
    out thmname; List.iter (fun i -> out " X"; out (string_of_int i)) fVall; List.iter (fun (x, _) -> out " x"; out (string_of_int x)) (* fvcl *) fvall; List.iter (fun (_, n) -> out " "; out n) ass; out " --> "; print_proof out ass p; out "."
    (* out thmname; List.iter (fun (x, _) -> out " x"; out (string_of_int x)) (\* fvcl *\) fvall; List.iter (fun (_, n) -> out " "; out n) ass; out " --> "; print_proof out ass p; out "." *)


  (* Export theorems with sharing *)

  let make_dependencies out ((thmname, pr, _) as p) =

    (* print_endline thmname; *)

    let dep_graph = Depgraph.Dep.create () in
    let proof_of_thm = Hashtbl.create (references pr) in
    Depgraph.Dep.add_thm dep_graph thmname;

    (* print_string "p = "; pp_proof print_string pr; print_newline (); *)

    make_dependencies_aux dep_graph proof_of_thm p;

    if
      (thmname <> (THEORY_NAME^"_DEF_T")) &&
        (thmname <> (THEORY_NAME^"_DEF__slash__backslash_")) &&
        (thmname <> (THEORY_NAME^"_DEF__equal__equal__greaterthan_")) &&
        (thmname <> (THEORY_NAME^"_DEF__exclamationmark_")) &&
        (thmname <> (THEORY_NAME^"_DEF__questionmark_")) &&
        (thmname <> (THEORY_NAME^"_DEF__backslash__slash_")) &&
        (thmname <> (THEORY_NAME^"_DEF_F"))&&
        (thmname <> (THEORY_NAME^"_DEF__tilde_"))
    then (
      Depgraph.Dep_top.iter_top (
        fun thm ->
          (try
               let p, h, t = Hashtbl.find proof_of_thm thm in
               export_thm out thm h t p
           with | Not_found -> failwith ("make_dependencies "^thm^": proof_of_thm not found\n"));
      ) dep_graph
    )


  (* let proof2nproof p = *)

  (*   let rec proof2nproof p = *)
  (*     match content_of p with *)
  (*       | Prefl t -> *)
  (*           let u = term2nterm t in *)
  (*           let ty = type_of u in *)
  (*           [(Nprefl (u, ty), heq ty u u)] *)

  (*       | Ptrans (p1, p2) -> *)
  (*           let l1 = proof2nproof p1 in *)
  (*           let (p'1, t1) = List.hd l1 in *)
  (*           let l'1 = List.tl l1 *)

  (*           let l2 = proof2nproof p2 in *)
  (*           let (p'2, t2) = List.hd l2 in *)
  (*           let l'2 = List.tl l2 in *)

  (*           (match t1, t2 with *)
  (*              | Napp (Napp (Ncst (Heq ty), u), v), Napp (Napp (Ncst (Heq _), _), w) -> (Nptrans (p'1, p'2, ty, u, v, w), heq ty u w)::(l'1@l'2) *)
  (*              | _, _ -> failwith "proof2nproof: rule trans incorrect") *)

  (*       | Pabs (p1, x, ty) -> *)
  (*           let l = proof2nproof p1 in *)
  (*           let (p', t) = List.hd l in *)
  (*           let l' = List.tl l in *)

  (*           match t with *)
  (*             | Napp (Napp (Ncst (Heq ty2), u), v) ->  *)

  (*       | _ -> failwith "proof2nproof: rule not implemented yet" in *)

  (*   fst (proof2nproof p) *)


  (* Saving theorems *)

  let the_proof_database = ref [];;

  let proof_database () = !the_proof_database

  let save_proof name p c_opt =
    the_proof_database := (name, p, c_opt)::(!the_proof_database)


  (* Main function: list of proofs exportation *)

  let export_list thmname_list =

    let path = ensure_export_directory THEORY_NAME in


    let rec proof_of_thm acc acc2 = function
      | [] -> acc, acc2
      | (s,p,c)::q ->
          if List.mem s thmname_list then
            proof_of_thm ((THEORY_NAME^"_"^(mfc s), reset_disk_info_of1 p, c)::acc) (acc2+1) q
          else
            proof_of_thm acc acc2 q in

    let l, total_thms = proof_of_thm [] 0 (proof_database ()) in


    (* Main file *)

    let file = open_out (Filename.concat path (THEORY_NAME^".dk")) in
    let count_file = ref 0 in
    let out s = (output_string file s; incr count_file; if !count_file = 1000 then (count_file := 0; flush file)) in
    out ";*** This file has been automatically generated from HOL-Light source files. ***\n";

    let date1 = Unix.time () in
    (* List.iter (fun th -> out "\n\n"; export_thm out th) l; *)
    List.iter (make_dependencies out) l;
    let date2 = Unix.time () in

    close_out file;

    print_string "Generated "; print_int !total; print_string " facts for "; print_int total_thms; print_string " theorems.\n";
    print_string "Exportation time: "; print_float (date2 -. date1); print_string "s.\n"


  (* Main function: all proofs exportation *)

  let export_saved_proofs () = export_list (List.map (fun (s,_,_) -> s) (proof_database ()))


  (* Main function: one proof exportation *)

  let export_one_proof name = export_list [name]


end;;


include Proofobjects;;
