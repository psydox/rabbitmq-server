%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2021 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_observer_cli_classic_queues).

-export([plugin_info/0]).
-export([attributes/1, sheet_header/0, sheet_body/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

plugin_info() ->
    #{
        module => rabbit_observer_cli_classic_queues,
        title => "Classic",
        shortcut => "CQ",
        sort_column => 4
    }.

attributes(State) ->
    Content1 = "Location of messages in classic queues.",
    Content2 = "Q, MQ and GQ are Erlang messages (total, mailbox and GS2 queue).",
    Content3 = "mem/disk are AMQP messages in memory or on disk.",
    Content4 = "pa/cf are messages pending acks or confirms.",
    Content5 = "qib/qibu/qsb are index/store buffer sizes, with qib = AMQP messages + qibu (acks).",
    {[
        [#{content => Content1, width => 133}],
        [#{content => Content2, width => 133}],
        [#{content => Content3, width => 133}],
        [#{content => Content4, width => 133}],
        [#{content => Content5, width => 133}]
    ], State}.

sheet_header() ->
    [
        #{title => "Pid", width => 12, shortcut => "P"},
        #{title => "Vhost", width => 10, shortcut => "V"},
        #{title => "Name", width => 26, shortcut => "N"},
        #{title => "", width => 5, shortcut => "Q"},
        #{title => "", width => 5, shortcut => "MQ"},
        #{title => "", width => 5, shortcut => "GQ"},
        #{title => "", width => 10, shortcut => "mem"},
        #{title => "", width => 10, shortcut => "disk"},
        #{title => "", width => 8, shortcut => "pa"},
        #{title => "", width => 8, shortcut => "cf"},
        #{title => "", width => 6, shortcut => "qib"},
        #{title => "", width => 6, shortcut => "qibu"},
        #{title => "", width => 6, shortcut => "qsb"}
    ].

sheet_body(State) ->
    Body = [begin
        #resource{name = Name, virtual_host = Vhost} = amqqueue:get_name(Q),
        case rabbit_amqqueue:pid_of(Q) of
            {error, not_found} ->
                ["dead", Vhost, unicode:characters_to_binary([Name, " (dead)"]),
                    0,0,0,0,0,0,0,0,0,0];
            Pid ->
                case process_info(Pid, message_queue_len) of
                    undefined ->
                        [Pid, Vhost, unicode:characters_to_binary([Name, " (dead)"]),
                            0,0,0,0,0,0,0,0,0,0];
                    {_, MsgQ} ->
                        GS2Q = rabbit_core_metrics:get_gen_server2_stats(Pid),
                        Info = rabbit_amqqueue:info(Q),
                        BQInfo = proplists:get_value(backing_queue_status, Info),
                        [
                            Pid, Vhost, Name,
                            MsgQ + GS2Q, MsgQ, GS2Q,
                            proplists:get_value(q3, BQInfo),
                            element(3, proplists:get_value(delta, BQInfo)),
                            proplists:get_value(num_pending_acks, BQInfo),
                            proplists:get_value(num_unconfirmed, BQInfo),
                            proplists:get_value(qi_buffer_size, BQInfo, 0),
                            proplists:get_value(qi_buffer_num_up, BQInfo, 0),
                            proplists:get_value(qs_buffer_size, BQInfo)
                        ]
                end
        end
    end || Q <- list_classic_queues()],
    {Body, State}.

%% This function gets all classic queues regardless of durable/exclusive status.
list_classic_queues() ->
    {atomic, Qs} =
        mnesia:sync_transaction(
          fun () ->
                  mnesia:match_object(rabbit_queue,
                                      amqqueue:pattern_match_on_type(rabbit_classic_queue),
                                      read)
          end),
    Qs.