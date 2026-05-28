%%%-------------------------------------------------------------------
%%% @doc Lobste.rs RSS filter.
%%%
%%% Copies priv/rss_config.json to the working directory then starts
%%% an rss_filter agent under its own name with specific capabilities.
%%% @end
%%%-------------------------------------------------------------------
-module(lobste_rs_rss_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

%%====================================================================
%% Application lifecycle
%%====================================================================

start(_Type, _Args) ->
    copy_config(),
    case lobste_rs_rss_filter_sup:start_link() of
        {ok, Pid} ->
            ok = start_pop_and_http(),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    catch cowboy:stop_listener(lobste_rs_rss_filter_query_listener),
    catch em_pop_sup:stop_node(lobste_rs_rss_filter),
    ok.

%%====================================================================
%% Capabilities and handler
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    rss_filter_app:base_capabilities() ++ [<<"lobsters">>, <<"programming">>, <<"tech">>, <<"curated">>].

-spec handle(binary(), map()) -> {list(), map()}.
handle(Body, Memory) ->
    rss_filter_app:handle(Body, Memory).

%%====================================================================
%% Internal
%%====================================================================

start_pop_and_http() ->
    PopPort   = application:get_env(lobste_rs_rss_filter, pop_port,   9462),
    QueryPort = application:get_env(lobste_rs_rss_filter, query_port, 9463),
    Seeds     = application:get_env(lobste_rs_rss_filter, pop_seeds,  []),
    Vec = em_filter_vec:from_capabilities(base_capabilities()),
    catch em_pop_sup:stop_node(lobste_rs_rss_filter),
    catch cowboy:stop_listener(lobste_rs_rss_filter_query_listener),
    {ok, PopPid} = em_pop_sup:start_node(lobste_rs_rss_filter, #{
        port            => PopPort,
        query_port      => QueryPort,
        vector          => Vec,
        max_peers       => 100,
        gossip_interval => 5_000
    }),
    lists:foreach(
        fun({H, P}) -> catch em_pop_node:add_peer(PopPid, H, P) end,
        Seeds),
    Dispatch = cowboy_router:compile([
        {'_', [{"/agent/query", em_filter_http,
                #{server => lobste_rs_rss_filter_server}}]}
    ]),
    {ok, _} = cowboy:start_clear(lobste_rs_rss_filter_query_listener,
                                  [{port, QueryPort}],
                                  #{env => #{dispatch => Dispatch}}),
    logger:notice("[lobste_rs_rss_filter] gossip port ~w  query port ~w",
                  [PopPort, QueryPort]),
    ok.

copy_config() ->
    case code:priv_dir(lobste_rs_rss_filter) of
        PrivDir when is_list(PrivDir) ->
            Src = filename:join(PrivDir, "rss_config.json"),
            file:copy(Src, "rss_config.json"),
            ok;
        {error, bad_name} ->
            ok
    end.
