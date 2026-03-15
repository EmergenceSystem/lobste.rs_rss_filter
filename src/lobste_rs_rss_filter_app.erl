%%%-------------------------------------------------------------------
%%% @doc Lobste.rs RSS filter application.
%%%
%%% Responsibility:
%%%   - copy priv/rss_config.json to working directory
%%%   - start rss_filter application
%%%
%%% rss_filter handles em_filter internally.
%%%-------------------------------------------------------------------
-module(lobste_rs_rss_filter_app).

-behaviour(application).

-export([start/2, stop/1]).

%%====================================================================
%% Application callbacks
%%====================================================================

start(_StartType, _StartArgs) ->
    copy_config(),
    application:ensure_all_started(rss_filter),
    {ok, self()}.

stop(_State) ->
    ok.

%%====================================================================
%% Internal
%%====================================================================

copy_config() ->
    case code:priv_dir(lobste_rs_rss_filter) of

        %% running in release
        PrivDir when is_list(PrivDir) ->
            Src = filename:join(PrivDir, "rss_config.json"),
            file:copy(Src, "rss_config.json"),
            ok;

        %% running in dev mode
        {error, bad_name} ->
            ok
    end.
