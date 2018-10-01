%%%-------------------------------------------------------------------
%%% @author Ulf Norell
%%% @copyright (C) 2017, Aeternity Anstalt
%%% @doc
%%%     Handle AEVM maps.
%%% @end
%%% Created : 28 Sep 2018
%%%-------------------------------------------------------------------
-module(aevm_eeevm_maps).

-export([ map_type/2
        , init_maps/0
        , empty/3
        , get/3
        , put/4
        , delete/3
        ]).

-include_lib("aesophia/src/aeso_data.hrl").

-export_type([map_id/0, maps/0]).

-opaque maps() :: #maps{}.

-type state()   :: state().
-type map_id()  :: non_neg_integer().
-type value()   :: aeso_data:binary_value().
-type typerep() :: aeso_sophia:type().

-type pmap() :: #pmap{}.

-spec init_maps() -> maps().
init_maps() -> #maps{}.

-spec map_type(map_id(), state()) -> {typerep(), typerep()}.
map_type(Id, State) ->
    {ok, Map} = get_map(Id, State),
    {Map#pmap.key_t, Map#pmap.val_t}.

-spec empty(typerep(), typerep(), state()) ->
        {map_id(), state()}.
empty(KeyType, ValType, State) ->
    Map = #pmap{ key_t  = KeyType,
                 val_t  = ValType,
                 parent = none,
                 data   = #{}},
    add_map(Map, State).

-spec get(map_id(), value(), state()) -> false | value().
get(Id, Key, State) ->
    {ok, Map} = get_map(Id, State),
    case Map#pmap.data of
        #{ Key := Val } ->
            case Val of
                tombstone               -> false;
                Val when is_binary(Val) -> Val
            end;
        _ ->
            case Map#pmap.parent of
                none     -> false;
                ParentId when ParentId < Id -> get(ParentId, Key, State)
                    %% Ensuring termination. ParentId will be smaller than Id
                    %% for any well-formed maps.
            end
    end.

-spec put(map_id(), value(), value(), state()) -> {map_id(), state()}.
put(Id, Key, Val, State) ->
    update(Id, Key, Val, State).

-spec delete(map_id(), value(), state()) -> {map_id(), state()}.
delete(Id, Key, State) ->
    update(Id, Key, tombstone, State).

-spec update(map_id(), value(), value() | tombstone, state()) -> {map_id(), state()}.
update(Id, Key, Val, State) ->
    {ok, Map} = get_map(Id, State),
    case Map#pmap.data of
        Data when is_map(Data) -> %% squash local updates
            add_map(Map#pmap{ data = Data#{Key => Val} }, State);
        stored -> %% not yet implemented
            add_map(Map#pmap{ parent = Id, data = #{Key => Val} }, State)
    end.

%% -- Internal functions -----------------------------------------------------

-spec get_map(map_id(), state()) -> {ok, pmap()} | {error, not_found}.
get_map(MapId, State) ->
    case aevm_eeevm_state:maps(State) of
        #maps{ maps = #{ MapId := Map } } -> {ok, Map};
        _ -> {error, not_found}
    end.

-spec add_map(pmap(), state()) -> {map_id(), state()}.
add_map(Map, State) ->
    Maps    = aevm_eeevm_state:maps(State),
    NewId   = Maps#maps.next_id,
    NewMaps = Maps#maps{ next_id = NewId + 1,
                         maps = (Maps#maps.maps)#{ NewId => Map } },
    {NewId, aevm_eeevm_state:set_maps(NewMaps, State)}.

