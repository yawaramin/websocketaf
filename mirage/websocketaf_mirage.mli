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

open Websocketaf

module type Server = sig
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

module Server (Flow : Mirage_flow.S) :
  Server with type flow = Flow.flow

module Server_with_conduit : sig
  include Server with type flow = Conduit_mirage.Flow.flow

  type t = Conduit_mirage.Flow.flow -> unit Lwt.t

  val connect:
    Conduit_mirage.t ->
    (Conduit_mirage.server -> t -> unit Lwt.t) Lwt.t
end

module type Client = sig
  type flow

  include Websocketaf_lwt.Client with type socket := flow
end

module Client (Flow : Mirage_flow.S) : Client with type flow = Flow.flow
