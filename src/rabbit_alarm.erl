%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2011 VMware, Inc.  All rights reserved.
%%

-module(rabbit_alarm).

-behaviour(gen_event).

-export([start/0, stop/0, register/2, on_node/2]).

-export([init/1, handle_call/2, handle_event/2, handle_info/2,
         terminate/2, code_change/3]).

-export([remote_conserve_memory/2]). %% Internal use only

-record(alarms, {alertees, alarmed_nodes}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-type(mfa_tuple() :: {atom(), atom(), list()}).
-spec(start/0 :: () -> 'ok').
-spec(stop/0 :: () -> 'ok').
-spec(register/2 :: (pid(), mfa_tuple()) -> boolean()).
-spec(on_node/2 :: ('up'|'down', node()) -> 'ok').

-endif.

%%----------------------------------------------------------------------------

start() ->
    ok = alarm_handler:add_alarm_handler(?MODULE, []),
    {ok, MemoryWatermark} = application:get_env(vm_memory_high_watermark),
    ok = case MemoryWatermark == 0 of
             true  -> ok;
             false -> rabbit_sup:start_restartable_child(vm_memory_monitor,
                                                         [MemoryWatermark])
         end,
    ok.

stop() ->
    ok = alarm_handler:delete_alarm_handler(?MODULE).

register(Pid, HighMemMFA) ->
    gen_event:call(alarm_handler, ?MODULE,
                   {register, Pid, HighMemMFA},
                   infinity).

on_node(Action, Node) ->
    gen_event:notify(alarm_handler, {node, Action, Node}).

remote_conserve_memory(Pid, Conserve) ->
    RemoteNode = node(Pid),
    %% Can't use alarm_handler:{set,clear}_alarm because that doesn't
    %% permit notifying a remote node.
    case Conserve of
        true  -> gen_event:notify(
                   {alarm_handler, RemoteNode},
                   {set_alarm, {{vm_memory_high_watermark, node()}, []}});
        false -> gen_event:notify(
                   {alarm_handler, RemoteNode},
                   {clear_alarm, {vm_memory_high_watermark, node()}})
    end.

%%----------------------------------------------------------------------------

init([]) ->
    {ok, #alarms{alertees      = dict:new(),
                 alarmed_nodes = sets:new()}}.

handle_call({register, Pid, HighMemMFA}, State) ->
    {ok, 0 < sets:size(State#alarms.alarmed_nodes),
     internal_register(Pid, HighMemMFA, State)};

handle_call(_Request, State) ->
    {ok, not_understood, State}.

handle_event({set_alarm, {{vm_memory_high_watermark, Node}, []}},
             State = #alarms{alarmed_nodes = AN}) ->
    AN1 = sets:add_element(Node, AN),
    ok = maybe_alert(AN, AN1, State#alarms.alertees, Node, true),
    {ok, State#alarms{alarmed_nodes = AN1}};

handle_event({clear_alarm, {vm_memory_high_watermark, Node}},
             State = #alarms{alarmed_nodes = AN}) ->
    AN1 = sets:del_element(Node, AN),
    ok = maybe_alert(AN, AN1, State#alarms.alertees, Node, false),
    {ok, State#alarms{alarmed_nodes = AN1}};

handle_event({node, up, Node}, State) ->
    %% Must do this via notify and not call to avoid possible deadlock.
    ok = gen_event:notify(
           {alarm_handler, Node},
           {register, self(), {?MODULE, remote_conserve_memory, []}}),
    {ok, State};

handle_event({node, down, Node}, State = #alarms{alarmed_nodes = AN}) ->
    AN1 = sets:del_element(Node, AN),
    ok = maybe_alert(AN, AN1, State#alarms.alertees, Node, false),
    {ok, State#alarms{alarmed_nodes = AN1}};

handle_event({register, Pid, HighMemMFA}, State) ->
    {ok, internal_register(Pid, HighMemMFA, State)};

handle_event(_Event, State) ->
    {ok, State}.

handle_info({'DOWN', _MRef, process, Pid, _Reason},
            State = #alarms{alertees = Alertess}) ->
    {ok, State#alarms{alertees = dict:erase(Pid, Alertess)}};

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%----------------------------------------------------------------------------

maybe_alert(Before, After, Alertees, AlarmNode, Action)
  when AlarmNode =:= node() ->
    %% If we have changed our alarm state, always inform the remotes.
    case {sets:is_element(AlarmNode, Before), sets:is_element(AlarmNode, After),
          Action} of
        {false, true,  true}  -> alert_remote(Action, Alertees);
        {true,  false, false} -> alert_remote(Action, Alertees);
        _                     -> ok
    end,
    maybe_alert_local(Before, After, Alertees, Action);
maybe_alert(Before, After, Alertees, _AlarmNode, Action) ->
    maybe_alert_local(Before, After, Alertees, Action).

maybe_alert_local(Before, After, Alertees, Action) ->
    %% If the overall alarm state has changed, inform the locals.
    case {sets:size(Before), sets:size(After), Action} of
        {0, 1, true}  -> alert_local(Action, Alertees);
        {1, 0, false} -> alert_local(Action, Alertees);
        _             -> ok
    end.

alert_local(Alert, Alertees) ->
    alert(Alert, Alertees, fun erlang:'=:='/2).

alert_remote(Alert, Alertees) ->
    alert(Alert, Alertees, fun erlang:'=/='/2).

alert(Alert, Alertees, NodeComparator) ->
    Node = node(),
    dict:fold(fun (Pid, {M, F, A}, Acc) ->
                      case NodeComparator(Node, node(Pid)) of
                          true  -> ok = erlang:apply(M, F, A ++ [Pid, Alert]),
                                   Acc;
                          false -> Acc
                      end
              end, ok, Alertees).

internal_register(Pid, {M, F, A} = HighMemMFA,
                  State = #alarms{alertees = Alertees}) ->
    _MRef = erlang:monitor(process, Pid),
    ok = case sets:is_element(node(), State#alarms.alarmed_nodes) of
             true  -> apply(M, F, A ++ [Pid, true]);
             false -> ok
         end,
    NewAlertees = dict:store(Pid, HighMemMFA, Alertees),
    State#alarms{alertees = NewAlertees}.
