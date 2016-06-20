(* Lightweight thread library for OCaml
 * http://www.ocsigen.org/lwt
 * Module Lwt_mutex
 * Copyright (C) 2005-2008 Jérôme Vouillon
 * Laboratoire PPS - CNRS Université Paris Diderot
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, with linking exceptions;
 * either version 2.1 of the License, or (at your option) any later
 * version. See COPYING file for details.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
 * 02111-1307, USA.
*)

open Lwt.Infix

type t = { mutable locked : bool; mutable waiters : (unit Lwt.u * bool ref) Lwt_sequence.t  }

let create () = { locked = false; waiters = Lwt_sequence.create () }

let unlock m =
  if m.locked then begin
    if Lwt_sequence.is_empty m.waiters then
      m.locked <- false
    else
      (* We do not use [Lwt.wakeup] here to avoid a stack overflow
         when unlocking a lot of threads. *)
      let wakener, is_locked_by_us = Lwt_sequence.take_l m.waiters in
      let () = is_locked_by_us := true in
      Lwt.wakeup_later wakener ()
  end

let rec lock m =
  if m.locked then
    let waiter, wakener = Lwt.task () in
    let is_locked_by_us = ref false in
    let node = Lwt_sequence.add_r (wakener, is_locked_by_us) m.waiters in
    let () = Lwt.on_cancel waiter (fun () -> Lwt_sequence.remove node) in
    Lwt.catch
      (fun () -> waiter)
      (fun e ->
         let () = if !is_locked_by_us then unlock m in
         Lwt.fail e
      )
  else
    let () = m.locked <- true in
    Lwt.return ()

let with_lock m f =
  Lwt.finalize
    (fun () -> Lwt.bind (lock m) (fun () -> f ()))
    (fun () ->
       let () = unlock m in
       Lwt.return_unit
    )

let is_locked m = m.locked

let is_empty m = Lwt_sequence.is_empty m.waiters
