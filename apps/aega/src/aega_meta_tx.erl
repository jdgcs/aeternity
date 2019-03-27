%%%=============================================================================
%%% @copyright 2019, Aeternity Anstalt
%%% @doc
%%%    Module defining the Meta transaction for Generalized Accounts
%%% @end
%%%=============================================================================
-module(aega_meta_tx).

-behavior(aetx).

-include_lib("apps/aecontract/src/aecontract.hrl").

%% Behavior API
-export([new/1,
         type/0,
         fee/1,
         gas/1,
         ttl/1,
         nonce/1,
         origin/1,
         check/3,
         process/3,
         signers/2,
         version/0,
         serialization_template/1,
         serialize/1,
         deserialize/2,
         for_client/1
        ]).
%% Additional getters
-export([abi_version/1,
         auth_data/1,
         auth_id/1,
         auth_id/2,
         ga_id/1,
         ga_pubkey/1,
         gas_limit/2,
         gas_price/1,
         tx/1
        ]).

-define(GA_META_TX_VSN, 1).
-define(GA_META_TX_TYPE, ga_meta_tx).

%% Should this be in a header file somewhere?
-define(PUB_SIZE, 32).

-define(is_non_neg_integer(X), (is_integer(X) andalso (X >= 0))).

-type amount() :: aect_contracts:amount().

-record(ga_meta_tx, {
          ga_id       :: aeser_id:id(),
          auth_data   :: binary(),
          abi_version :: aect_contracts:abi_version(),
          gas         :: amount(),
          gas_price   :: amount(),
          fee         :: amount(),
          ttl         :: aetx:tx_ttl(),
          tx          :: aetx:tx()
        }).

-opaque tx() :: #ga_meta_tx{}.

-export_type([tx/0]).

%%%===================================================================
%%% Getters

-spec ga_id(tx()) -> aeser_id:id().
ga_id(#ga_meta_tx{ga_id = GAId}) ->
    GAId.

-spec ga_pubkey(tx()) -> aec_keys:pubkey().
ga_pubkey(#ga_meta_tx{ga_id = GAId}) ->
    aeser_id:specialize(GAId, account).

-spec abi_version(tx()) -> aect_contracts:abi_version().
abi_version(#ga_meta_tx{abi_version = ABI}) ->
    ABI.

-spec gas(tx()) -> amount().
gas(#ga_meta_tx{gas = Gas}) ->
    Gas.

-spec gas_limit(tx(), non_neg_integer()) -> amount().
gas_limit(#ga_meta_tx{gas = Gas, tx = InnerTx}, Height) ->
    aetx:gas_limit(InnerTx, Height) + Gas.

-spec gas_price(tx()) -> amount().
gas_price(#ga_meta_tx{gas_price = GasPrice}) ->
    GasPrice.

-spec auth_data(tx()) -> binary().
auth_data(#ga_meta_tx{auth_data = AuthData}) ->
    AuthData.

-spec auth_id(tx()) -> aect_call:id().
auth_id(#ga_meta_tx{auth_data = AuthData} = Tx) ->
    auth_id(ga_pubkey(Tx), AuthData).

-spec auth_id(binary(), binary()) -> aect_call:id().
auth_id(GAPubkey, AuthData) ->
    aec_hash:hash(pubkey, <<GAPubkey/binary, AuthData/binary>>).

-spec tx(tx()) -> aetx:tx().
tx(#ga_meta_tx{tx = Tx}) ->
    Tx.

%%%===================================================================
%%% Behavior API

-spec fee(tx()) -> integer().
fee(#ga_meta_tx{fee = Fee}) ->
    Fee.

-spec ttl(tx()) -> aetx:tx_ttl().
ttl(#ga_meta_tx{ttl = TTL}) ->
    TTL.

-spec new(map()) -> {ok, aetx:tx()}.
new(#{ga_id       := GAId,
      auth_data   := AuthData,
      abi_version := ABIVersion,
      gas         := Gas,
      gas_price   := GasPrice,
      fee         := Fee,
      tx          := InnerTx} = Args) ->
    account = aeser_id:specialize_type(GAId),
    Tx = #ga_meta_tx{ga_id       = GAId,
                     auth_data   = AuthData,
                     abi_version = ABIVersion,
                     gas         = Gas,
                     gas_price   = GasPrice,
                     fee         = Fee,
                     ttl         = maps:get(ttl, Args, 0),
                     tx          = InnerTx},
    {ok, aetx:new(?MODULE, Tx)}.

-spec type() -> atom().
type() ->
    ?GA_META_TX_TYPE.

-spec nonce(tx()) -> non_neg_integer().
nonce(#ga_meta_tx{}) ->
    0.

-spec origin(tx()) -> aec_keys:pubkey().
origin(#ga_meta_tx{} = Tx) ->
    ga_pubkey(Tx).

%% Owner should exist, and have enough funds for the fee, the amount
%% the deposit and the gas
-spec check(tx(), aec_trees:trees(), aetx_env:env()) -> {ok, aec_trees:trees()} | {error, term()}.
check(#ga_meta_tx{}, Trees,_Env) ->
    %% Checks in process/3
    {ok, Trees}.

-spec signers(tx(), aec_trees:trees()) -> {ok, [aec_keys:pubkey()]}.
signers(#ga_meta_tx{}, _) ->
    {ok, []}.

-spec process(tx(), aec_trees:trees(), aetx_env:env()) -> {ok, aec_trees:trees(), aetx_env:env()}.
process(#ga_meta_tx{} = Tx, Trees, Env0) ->
    AuthInstructions =
        aec_tx_processor:ga_meta_tx_instructions(
          ga_pubkey(Tx),
          auth_data(Tx),
          abi_version(Tx),
          gas(Tx),
          gas_price(Tx),
          fee(Tx),
          tx(Tx)),
    Env = add_tx_hash(Env0, tx(Tx)),
    case aec_tx_processor:eval(AuthInstructions, Trees, Env) of
        {ok, Trees1, Env1} ->
            Env2 = set_ga_context(Env1, Tx),
            case aetx:process(tx(Tx), Trees1, Env2) of
                {ok, Trees2, Env3} ->
                    {ok, Trees2, reset_ga_context(Env3, aetx_env:context(Env1))};
                %% GA_TODO: How carefully should we try to avoid this?
                %%          It will be a confusing case for users...
                {error, _} =_E  ->
                    {ok, Trees1, Env1}
            end;
        Err = {error, _} ->
            Err
    end.

add_tx_hash(Env0, Aetx) ->
    BinForNetwork = aec_governance:add_network_id(aetx:serialize_to_binary(Aetx)),
    aetx_env:set_ga_tx_hash(Env0, aec_hash:hash(tx, BinForNetwork)).

set_ga_context(Env0, Tx) ->
    Env1 = aetx_env:set_context(Env0, aetx_ga),
    Env2 = aetx_env:set_ga_id(Env1, ga_pubkey(Tx)),
    Env3 = aetx_env:set_ga_nonce(Env2, auth_id(Tx)),
    aetx_env:set_ga_tx_hash(Env3, undefined).

reset_ga_context(Env0, Context) ->
    Env1 = aetx_env:set_context(Env0, Context),
    Env2 = aetx_env:set_ga_id(Env1, undefined),
    aetx_env:set_ga_nonce(Env2, undefined).

serialize(#ga_meta_tx{ga_id       = GAId,
                      auth_data   = AuthData,
                      abi_version = ABIVersion,
                      fee         = Fee,
                      gas         = Gas,
                      gas_price   = GasPrice,
                      ttl         = TTL,
                      tx          = InnerTx}) ->
    SerTx = aetx:serialize_to_binary(InnerTx),
    {version(),
     [ {ga_id, GAId}
     , {auth_data, AuthData}
     , {abi_version, ABIVersion}
     , {fee, Fee}
     , {gas, Gas}
     , {gas_price, GasPrice}
     , {ttl, TTL}
     , {tx, SerTx}
     ]}.

deserialize(?GA_META_TX_VSN,
            [ {ga_id, GAId}
            , {auth_data, AuthData}
            , {abi_version, ABIVersion}
            , {fee, Fee}
            , {gas, Gas}
            , {gas_price, GasPrice}
            , {ttl, TTL}
            , {tx, SerTx}]) ->
    account = aeser_id:specialize_type(GAId),
    Tx = aetx:deserialize_from_binary(SerTx),
    #ga_meta_tx{ga_id       = GAId,
                auth_data   = AuthData,
                abi_version = ABIVersion,
                fee         = Fee,
                gas         = Gas,
                gas_price   = GasPrice,
                ttl         = TTL,
                tx          = Tx}.

serialization_template(?GA_META_TX_VSN) ->
    [ {ga_id, id}
    , {auth_data, binary}
    , {abi_version, int}
    , {fee, int}
    , {gas, int}
    , {gas_price, int}
    , {ttl, int}
    , {tx, binary}
    ].

for_client(#ga_meta_tx{ ga_id       = GAId,
                        auth_data   = AuthData,
                        abi_version = ABIVersion,
                        fee         = Fee,
                        gas         = Gas,
                        gas_price   = GasPrice,
                        ttl         = TTL,
                        tx          = InnerTx}) ->
    #{<<"ga_id">>       => aeser_api_encoder:encode(id_hash, GAId),
      <<"auth_data">>   => aeser_api_encoder:encode(contract_bytearray, AuthData),
      <<"abi_version">> => aeu_hex:hexstring_encode(<<ABIVersion:16>>),
      <<"fee">>         => Fee,
      <<"gas">>         => Gas,
      <<"gas_price">>   => GasPrice,
      <<"ttl">>         => TTL,
      <<"tx">>          => aetx:serialize_for_client(InnerTx)}.

%%%===================================================================
%%% Internal functions

-spec version() -> non_neg_integer().
version() ->
    ?GA_META_TX_VSN.

