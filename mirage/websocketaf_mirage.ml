(*----------------------------------------------------------------------------
    Copyright (c) 2018 Inhabited Type LLC.
    Copyright (c) 2019 António Nuno Monteiro

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    3. Neither the name of the author nor the names of his contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE CONTRIBUTORS ``AS IS'' AND ANY EXPRESS
    OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR
    ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
    STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
  ----------------------------------------------------------------------------*)

open Lwt.Infix

module Make_IO (Flow: Mirage_flow.S) :
  Websocketaf_lwt.IO with type socket = Flow.flow and type addr = unit = struct
  type socket = Flow.flow
  type addr = unit

  let shutdown flow =
    Flow.close flow

  let shutdown_receive flow =
    Lwt.async (fun () -> shutdown flow)

  let shutdown_send flow =
    Lwt.async (fun () -> shutdown flow)

  let close flow = shutdown flow

  let read flow bigstring ~off ~len:_ =
    Lwt.catch
      (fun () ->
        Flow.read flow >|= function
        | Ok (`Data buf) ->
          Bigstringaf.blit
            buf.buffer
            ~src_off:buf.off bigstring
            ~dst_off:off
            ~len:buf.len;
          `Ok buf.len
        | Ok `Eof -> `Eof
        | Error error ->
          raise (Failure (Format.asprintf "%a" Flow.pp_error error)))
      (fun exn ->
        shutdown flow >>= fun () ->
        Lwt.fail exn)

  let writev flow = fun iovecs ->
      let cstruct_iovecs = List.map (fun {Faraday.buffer; off; len} ->
        Cstruct.of_bigarray ~off ~len buffer)
        iovecs
      in

      Lwt.catch
        (fun () ->
          Flow.writev flow cstruct_iovecs >|= fun x ->
          match x with
          | Ok () ->
            `Ok (Cstruct.lenv cstruct_iovecs)
          | Error `Closed ->
            `Closed
          | Error other_error ->
            raise (Failure (Format.asprintf "%a" Flow.pp_write_error other_error)))
        (fun exn ->
          shutdown flow >>= fun () ->
          Lwt.fail exn)
end

module Server (Flow : Mirage_flow.S) = struct
  type flow = Flow.flow

  include Websocketaf_lwt.Server (Make_IO (Flow))

  let create_connection_handler ?config ~websocket_handler ~error_handler =
    fun flow ->
      let websocket_handler = fun () -> websocket_handler in
      let error_handler = fun () -> error_handler in
      create_connection_handler ?config ~websocket_handler ~error_handler () flow

  let create_upgraded_connection_handler ?config ~websocket_handler ~error_handler =
    fun flow ->
      let websocket_handler = fun () -> websocket_handler in
      create_upgraded_connection_handler ?config ~websocket_handler ~error_handler () flow
end

(* Almost like the `Websocketaf_lwt.Server` module type but we don't need the
 * client address argument in Mirage. It's somewhere else. *)
module type Server = sig
  open Websocketaf
  type flow

  val create_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : (Wsd.t -> Server_connection.input_handlers)
    -> error_handler : Httpaf.Server_connection.error_handler
    -> flow
    -> unit Lwt.t

  val create_upgraded_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : (Wsd.t -> Server_connection.input_handlers)
    -> error_handler : Server_connection.error_handler
    -> flow
    -> unit Lwt.t

  val respond_with_upgrade
  : ?headers : Httpaf.Headers.t
  -> (flow, unit Lwt.t) Httpaf.Reqd.t
  -> (flow -> unit Lwt.t)
  -> (unit, string) Lwt_result.t
end

module Server_with_conduit = struct
  open Conduit_mirage
  include Server (Conduit_mirage.Flow)

  type t = Conduit_mirage.Flow.flow -> unit Lwt.t

  let listen handler flow =
    Lwt.finalize
      (fun () -> handler flow)
      (fun () -> Flow.close flow)

  let connect t =
    let listen s f = Conduit_mirage.listen t s (listen f) in
    Lwt.return listen
end

module type Client = sig
  type flow

  include Websocketaf_lwt.Client with type socket := flow
end

module Client (Flow : Mirage_flow.S) = struct
    type flow = Flow.flow

    include Websocketaf_lwt.Client (Make_IO (Flow))
end
