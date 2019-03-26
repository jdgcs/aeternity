%%%-------------------------------------------------------------------
%%% @copyright (C) 2019, Aeternity Anstalt
%%% @doc CT test suite for Generalized accounts
%%% @end
%%%-------------------------------------------------------------------
-module(aega_SUITE).

%% common_test exports
-export([ all/0
        , groups/0
        , init_per_group/2
        , end_per_group/2
        , init_per_testcase/2
        ]).

-include_lib("aecontract/include/hard_forks.hrl").

%% test case exports
-export([ ga_attach/1
        , ga_double_attach_fail/1
        , ga_spend_to/1
        , ga_spend_from/1
        , ga_failed_auth/1
        , ga_contract_create/1
        , ga_contract_call/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-include_lib("apps/aecore/include/blocks.hrl").
-include_lib("apps/aecontract/src/aecontract.hrl").

-define(MINER_PUBKEY, <<12345:?MINER_PUB_BYTES/unit:8>>).
-define(BENEFICIARY_PUBKEY, <<12345:?BENEFICIARY_PUB_BYTES/unit:8>>).

-define(CHAIN_RELATIVE_TTL_MEMORY_ENCODING(X), {variant, 0, [X]}).
-define(CHAIN_ABSOLUTE_TTL_MEMORY_ENCODING(X), {variant, 1, [X]}).

-define(AESOPHIA_1, 1).
-define(AESOPHIA_2, 2).
-define(LATEST_AESOPHIA, ?AESOPHIA_2).

%%%===================================================================
%%% Common test framework
%%%===================================================================

all() ->
    [{group, all}].

groups() ->
    [ {all, [], [ ga_attach
                , ga_double_attach_fail
                , ga_spend_to
                , ga_spend_from
                , ga_failed_auth
                , ga_contract_create
                , ga_contract_call
                ]}
    ].

init_per_group(all, Cfg) ->
    meck:expect(aec_hard_forks, protocol_effective_at_height,
                fun(_) -> ?FORTUNA_PROTOCOL_VSN end),
    [{sophia_version, ?AESOPHIA_2}, {vm_version, ?VM_AEVM_SOPHIA_2},
     {protocol, fortuna} | Cfg];
%% init_per_group(vm_interaction, Cfg) ->
%%     Height = 10,
%%     Fun = fun(H) when H <  Height -> ?ROMA_PROTOCOL_VSN;
%%              (H) when H >= Height -> ?MINERVA_PROTOCOL_VSN
%%           end,
%%     meck:expect(aec_hard_forks, protocol_effective_at_height, Fun),
%%     [{sophia_version, ?AESOPHIA_2}, {vm_version, ?VM_AEVM_SOPHIA_2},
%%      {fork_height, Height},
%%      {protocol, minerva} | Cfg];
init_per_group(_Grp, Cfg) ->
    Cfg.

end_per_group(Grp, Cfg) when Grp =:= all ->
    meck:unload(aec_hard_forks),
    Cfg;
end_per_group(_Grp, Cfg) ->
    Cfg.

%% Process dict magic in the right process ;-)
init_per_testcase(_TC, Config) ->
    VmVersion = ?config(vm_version, Config),
    SophiaVersion = ?config(sophia_version, Config),
    ProtocolVersion = case ?config(protocol, Config) of
                          roma    -> ?ROMA_PROTOCOL_VSN;
                          minerva -> ?MINERVA_PROTOCOL_VSN;
                          fortuna -> ?FORTUNA_PROTOCOL_VSN
                      end,
    put('$vm_version', VmVersion),
    put('$sophia_version', SophiaVersion),
    put('$protocol_version', ProtocolVersion),
    Config.

-define(skipRest(Res, Reason),
    case Res of
        true  -> throw({skip, {skip_rest, Reason}});
        false -> ok
    end).

-define(call(Fun, X),                call(Fun, fun Fun/2, [X])).
-define(call(Fun, X, Y),             call(Fun, fun Fun/3, [X, Y])).
-define(call(Fun, X, Y, Z),          call(Fun, fun Fun/4, [X, Y, Z])).
-define(call(Fun, X, Y, Z, U),       call(Fun, fun Fun/5, [X, Y, Z, U])).
-define(call(Fun, X, Y, Z, U, V),    call(Fun, fun Fun/6, [X, Y, Z, U, V])).
-define(call(Fun, X, Y, Z, U, V, W), call(Fun, fun Fun/7, [X, Y, Z, U, V, W])).

%%%===================================================================
%%% Attach tests
%%%===================================================================

ga_attach(_Cfg) ->
    state(aect_test_utils:new_state()),
    Acc1 = ?call(new_account, 10000000 * aec_test_utils:min_gas_price()),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),
    ok.

ga_double_attach_fail(_Cfg) ->
    state(aect_test_utils:new_state()),
    Acc1 = ?call(new_account, 10000000 * aec_test_utils:min_gas_price()),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),

    {failed, not_a_basic_account} =
        ?call(attach, Acc1, "simple_auth", "authorize", ["0"], #{fail => true}),

    ok.

ga_spend_to(_Cfg) ->
    state(aect_test_utils:new_state()),
    MinGP = aec_test_utils:min_gas_price(),
    Acc1 = ?call(new_account, 10000000 * MinGP),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),

    Acc2 = ?call(new_account, 10000000 * MinGP),

    PreBalance = ?call(account_balance, Acc1),
    ok = ?call(spend, Acc2, Acc1, 500,  20000 * MinGP),
    PostBalance = ?call(account_balance, Acc1),
    ?assertMatch({X, Y} when X + 500 == Y, {PreBalance, PostBalance}),

    ok.

ga_spend_from(_Cfg) ->
    state(aect_test_utils:new_state()),
    MinGP = aec_test_utils:min_gas_price(),
    Acc1 = ?call(new_account, 10000000 * MinGP),
    Acc2 = ?call(new_account, 10000000 * MinGP),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),

    InnerSpendTx = spend_tx(#{sender_id    => aeser_id:create(account, Acc1),
                              recipient_id => aeser_id:create(account, Acc2),
                              amount       => 500,
                              fee          => 20000 * MinGP}),
    AuthData = make_calldata("simple_auth", "authorize", ["123", "1"]),

    PreBalance = ?call(account_balance, Acc2),
    {ok, _} = ?call(meta, Acc1, AuthData, InnerSpendTx),
    PostBalance = ?call(account_balance, Acc2),
    ?assertMatch({X, Y} when X + 500 == Y, {PreBalance, PostBalance}),

    ok.

ga_failed_auth(_Cfg) ->
    state(aect_test_utils:new_state()),
    MinGP = aec_test_utils:min_gas_price(),
    Acc1 = ?call(new_account, 10000000 * MinGP),
    Acc2 = ?call(new_account, 10000000 * MinGP),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),

    InnerSpendTx = spend_tx(#{sender_id    => aeser_id:create(account, Acc1),
                              recipient_id => aeser_id:create(account, Acc2),
                              amount       => 500,
                              fee          => 20000 * MinGP}),
    AuthData = make_calldata("simple_auth", "authorize", ["1234", "1"]),

    {failed, authentication_failed} =
        ?call(meta, Acc1, AuthData, InnerSpendTx, #{fail => true}),

    ok.

ga_contract_create(_Cfg) ->
    state(aect_test_utils:new_state()),
    MinGP = aec_test_utils:min_gas_price(),
    Acc1 = ?call(new_account, 1000000000 * MinGP),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),

    CreateTx = ?call(inner_create_tx, Acc1, "identity", []),
    AuthData = make_calldata("simple_auth", "authorize", ["123", "1"]),

    {ok, #{init_res := ok}} = ?call(meta, Acc1, AuthData, CreateTx),

    ok.

ga_contract_call(_Cfg) ->
    state(aect_test_utils:new_state()),
    MinGP = aec_test_utils:min_gas_price(),
    Acc1 = ?call(new_account, 1000000000 * MinGP),
    {ok, ok} = ?call(attach, Acc1, "simple_auth", "authorize", ["123"]),

    CreateTx = ?call(inner_create_tx, Acc1, "identity", []),
    {ok, #{src := Src}} = get_contract("simple_auth"),
    AuthData = make_calldata(Src, "authorize", ["123", "1"]),

    {ok, #{init_res := ok, ct_pubkey := Ct}} = ?call(meta, Acc1, AuthData, CreateTx),

    AuthData2 = make_calldata(Src, "authorize", ["123", "2"]),
    CallTx = ?call(inner_call_tx, Acc1, Ct, "identity", "main", ["42"]),

    {ok, #{call_res := ok, call_val := Val}} = ?call(meta, Acc1, AuthData2, CallTx),
    ?assertMatch("42", decode_call_result("identity", "main", ok, Val)),

    ok.

%%%===================================================================
%%% Test framework
%%%===================================================================

sign_and_apply_transaction(Tx, PrivKey, S1, Height) ->
    SignedTx = aec_test_utils:sign_tx(Tx, PrivKey),
    apply_transaction(SignedTx, S1, Height).

apply_transaction(Tx, S1, Height) ->
    Trees    = aect_test_utils:trees(S1),
    Env0     = aetx_env:tx_env(Height),
    Env      = aetx_env:set_beneficiary(Env0, ?BENEFICIARY_PUBKEY),
    case aec_block_micro_candidate:apply_block_txs_strict([Tx], Trees, Env) of
        {ok, [Tx], Trees1, _} ->
            S2 = aect_test_utils:set_trees(Trees1, S1),
            {ok, S2};
        {error, R} ->
            {error, R, S1}
    end.

%% make_contract(PubKey, Code, S) ->
%%     Tx = create_tx(PubKey, #{ code => Code }, S),
%%     {contract_create_tx, CTx} = aetx:specialize_type(Tx),
%%     aect_contracts:new(CTx).

%% make_call(PubKey, ContractKey,_Call,_S) ->
%%     aect_call:new(aeser_id:create(account, PubKey), 0,
%%                   aeser_id:create(contract, ContractKey), 1, 1).

state()  -> get(the_state).
state(S) -> put(the_state, S).

%% get_contract_state(Contract) ->
%%     S = state(),
%%     {{value, C}, _} = lookup_contract_by_id(Contract, S),
%%     get_ct_store(C).

call(Name, Fun, Xs) ->
    Fmt = string:join(lists:duplicate(length(Xs), "~p"), ", "),
    Xs1 = [ case X of
                <<Pre:32, _:28/unit:8>> -> <<Pre:32>>;
                _ -> X
            end || X <- Xs ],
    io:format("~p(" ++ Fmt ++ ") ->\n", [Name | Xs1]),
    R = call(Fun, Xs),
    io:format("Response:  ~p\n", [R]),
    R.

call(Fun, Xs) when is_function(Fun, 1 + length(Xs)) ->
    S = state(),
    {R, S1} = try apply(Fun, Xs ++ [S])
              catch
                _:{fail, Rx, Sx} -> {{failed, Rx}, Sx};
                _:{fail, Error} -> error(Error);
                _:Reason -> {{'EXIT', Reason, erlang:get_stacktrace()}, S}
              end,
    state(S1),
    R.

%% perform_pre_transformations(Height, S) ->
%%     Trees = aec_trees:perform_pre_transformations(aect_test_utils:trees(S), Height),
%%     {ok, aect_test_utils:set_trees(Trees, S)}.

new_account(Balance, S) ->
    aect_test_utils:setup_new_account(Balance, S).

%% insert_contract(Account, Code, S) ->
%%     Contract  = make_contract(Account, Code, S),
%%     Contracts = aect_state_tree:insert_contract(Contract, aect_test_utils:contracts(S)),
%%     {Contract, aect_test_utils:set_contracts(Contracts, S)}.

%% insert_call(Sender, Contract, Fun, S) ->
%%     ContractPubkey = aect_contracts:pubkey(Contract),
%%     Call           = make_call(Sender, ContractPubkey, Fun, S),
%%     CallTree       = aect_call_state_tree:insert_call(Call, aect_test_utils:calls(S)),
%%     {Call, aect_test_utils:set_calls(CallTree, S)}.

%% get_contract(Contract0, S) ->
%%     ContractPubkey = aect_contracts:pubkey(Contract0),
%%     Contracts      = aect_test_utils:contracts(S),
%%     Contract       = aect_state_tree:get_contract(ContractPubkey, Contracts),
%%     {Contract, S}.

%% lookup_contract_by_id(ContractKey, S) ->
%%     Contracts = aect_test_utils:contracts(S),
%%     X         = aect_state_tree:lookup_contract(ContractKey, Contracts),
%%     {X, S}.

%% get_call(Contract0, Call0, S) ->
%%     CallId         = aect_call:id(Call0),
%%     ContractPubkey = aect_contracts:pubkey(Contract0),
%%     CallTree       = aect_test_utils:calls(S),
%%     Call           = aect_call_state_tree:get_call(ContractPubkey, CallId, CallTree),
%%     {Call, S}.

%% state_tree(_Cfg) ->
%%     state(aect_test_utils:new_state()),
%%     Acc1  = ?call(new_account, 100),
%%     Ct1   = ?call(insert_contract, Acc1, <<"Code for C1">>),
%%     Ct1   = ?call(get_contract, Ct1),
%%     Acc2  = ?call(new_account, 50),
%%     Acc3  = ?call(new_account, 30),
%%     Ct2   = ?call(insert_contract, Acc2, <<"Code for C2">>),
%%     Ct2   = ?call(get_contract, Ct2),
%%     Ct1   = ?call(get_contract, Ct1),
%%     Call1 = ?call(insert_call, Acc3, Ct1, <<"Ct1.foo">>),
%%     Call2 = ?call(insert_call, Acc2, Ct1, <<"Ct1.bar">>),
%%     Call1 = ?call(get_call, Ct1, Call1),
%%     Call2 = ?call(get_call, Ct1, Call2),
%%     Ct1   = ?call(get_contract, Ct1),
%%     <<"Code for C1">> = aect_contracts:code(Ct1),
%%     ok.

%%%===================================================================
%%% More elaborate Sophia contracts
%%%===================================================================
vm_version() ->
    case get('$vm_version') of
        undefined -> aect_test_utils:latest_sophia_vm_version();
        X         -> X
    end.

%% protocol_version() ->
%%     case get('$protocol_version') of
%%         undefined -> aect_test_utils:latest_protocol_version();
%%         X         -> X
%%     end.

sophia_version() ->
    case get('$sophia_version') of
        undefined -> ?LATEST_AESOPHIA;
        X         -> X
    end.

spend_tx(Spec0) ->
    Spec = maps:merge(spend_tx_default(), Spec0),
    {ok, Tx} = aec_spend_tx:new(Spec),
    Tx.

spend(From, To, Amount, Fee, State) ->
    spend(From, To, Amount, Fee, #{}, State).

spend(From, To, Amount, Fee, Opts, State) ->
    FromId = aeser_id:create(account, From),
    ToId = aeser_id:create(account, To),
    PrivKey = aect_test_utils:priv_key(From, State),
    SpendSpec = #{sender_id => FromId, recipient_id => ToId,
                  amount => Amount, fee => Fee,
                  nonce => aect_test_utils:next_nonce(From, State) },
    SpendTx = spend_tx(SpendSpec),
    Height  = maps:get(height, Opts, 1),
    PrivKey = aect_test_utils:priv_key(From, State),
    case sign_and_apply_transaction(SpendTx, PrivKey, State, Height) of
        {ok, TmpS} -> {ok, TmpS};
        {error, R,_TmpS} -> error(R)
    end.

spend_tx_default() ->
    #{sender_id    => aeser_id:create(account, <<0:256>>),
      recipient_id => aeser_id:create(account, <<0:256>>),
      amount       => 123456,
      fee          => 25000 * aec_test_utils:min_gas_price(),
      nonce        => 0,
      payload      => <<>>}.

attach(Owner, Contract, AuthFun, Args, S) ->
    attach(Owner, Contract, AuthFun, Args, #{}, S).

attach(Owner, Contract, AuthFun, Args, Opts, S) ->
    case get_contract(Contract) of
        {ok, #{src := Src, bytecode := C, map := #{type_info := TI}}} ->
            Fail  = maps:get(fail, Opts, false),
            Nonce = aect_test_utils:next_nonce(Owner, S),
            Calldata = make_calldata(Src, "init", Args),
            {ok, AuthFunHash} = aeso_abi:type_hash_from_function_name(list_to_binary(AuthFun), TI),
            Options1 = maps:merge(#{nonce => Nonce, code => C,
                                    auth_fun => AuthFunHash, call_data => Calldata},
                                  maps:without([height, return_return_value, return_gas_used, fail], Opts)),
            AttachTx = ga_attach_tx(Owner, Options1, S),
            Height   = maps:get(height, Opts, 1),
            PrivKey  = aect_test_utils:priv_key(Owner, S),
            S1       = case sign_and_apply_transaction(AttachTx, PrivKey, S, Height) of
                           {ok, TmpS} when not Fail -> TmpS;
                           {ok,_TmpS} when Fail -> error({error, succeeded});
                           {error, R,_TmpS} when not Fail -> error(R);
                           {error, R, TmpS} when Fail -> throw({fail, R, TmpS})
                       end,
            ConKey   = aect_contracts:compute_contract_pubkey(Owner, Nonce),
            CallKey  = aect_call:id(Owner, Nonce, ConKey),
            CallTree = aect_test_utils:calls(S1),
            Call     = aect_call_state_tree:get_call(ConKey, CallKey, CallTree),

            %% Result1  =
            %%     case maps:get(return_return_value, Opts, false) of
            %%         false -> Result0;
            %%         true  -> {Result0, {aect_call:return_type(Call), aect_call:return_value(Call)}}
            %%     end,
            %% case maps:get(return_gas_used, Opts, false) of
            %%     false -> {{ok, Result1}, S1};
            %%     true  -> {{ok, Result1, aect_call:gas_used(Call)}, S1}
            %% end.
            {{ok, aect_call:return_type(Call)}, S1};
        _ ->
            error(bad_contract)
    end.

ga_attach_tx(PubKey, Spec0, State) ->
    Spec = maps:merge(ga_attach_tx_default(PubKey, State), Spec0),
    {ok, Tx} = aega_attach_tx:new(Spec),
    Tx.

ga_attach_tx_default(PubKey, State) ->
    #{ fee         => 1000000 * aec_test_utils:min_gas_price()
     , owner_id    => aeser_id:create(account, PubKey)
     , nonce       => try aect_test_utils:next_nonce(PubKey, State) catch _:_ -> 0 end
     , code        => aect_test_utils:dummy_bytecode()
     , auth_fun    => <<"NOT A FUNCTION">>
     , call_data   => <<"NOT ENCODED ACCORDING TO ABI">>
     , vm_version  => aect_test_utils:latest_sophia_vm_version()
     , abi_version => aect_test_utils:latest_sophia_abi_version()
     , gas         => 10000
     , gas_price   => 1 * aec_test_utils:min_gas_price()
     , ttl         => 0
     }.

meta(Owner, AuthData, InnerTx, S) ->
    meta(Owner, AuthData, InnerTx, #{}, S).

meta(Owner, AuthData, InnerTx, Opts, S) ->
    Fail  = maps:get(fail, Opts, false),
    Options1 = maps:merge(#{auth_data => AuthData, tx => InnerTx},
                          maps:without([height, return_return_value, return_gas_used, fail], Opts)),
    MetaTx  = ga_meta_tx(Owner, Options1, S),
    SMetaTx = aetx_sign:new(MetaTx, []),
    Height  = maps:get(height, Opts, 1),
    S1      = case apply_transaction(SMetaTx, S, Height) of
                  {ok, TmpS} when not Fail -> TmpS;
                  {ok,_TmpS} when Fail -> error({error, succeeded});
                  {error, R,_TmpS} when not Fail -> error(R);
                  {error, R, TmpS} when Fail -> throw({fail, R, TmpS})
              end,

    %% Getting here means authentication passed
    CallKey  = aec_hash:hash(pubkey, <<Owner/binary, AuthData/binary>>),
    CallTree = aect_test_utils:calls(S1),
    Call     = aect_call_state_tree:get_call(Owner, CallKey, CallTree),

    GasUsed = aect_call:gas_used(Call),
    AuthCost = aetx:fee(MetaTx) + aetx:gas_price(MetaTx) * GasUsed,
    Res0 = #{ auth_gas => GasUsed, auth_cost => AuthCost },

    Res =
        case aetx:specialize_type(InnerTx) of
            {spend_tx, _SpendTx} ->
                {ok, Res0#{ total_cost => AuthCost + aetx:fee(InnerTx) }};
            {contract_create_tx, _CCTx} ->
                ContractKey = aect_contracts:compute_contract_pubkey(Owner, CallKey),
                InitCall    = aect_call_state_tree:get_call(ContractKey, CallKey, CallTree),
                {ok, Res0#{ ct_pubkey => ContractKey
                          , init_res  => aect_call:return_type(InitCall) }};
            {contract_call_tx, CCTx} ->
                ContractKey = aect_call_tx:contract_pubkey(CCTx),
                InnerCall   = aect_call_state_tree:get_call(ContractKey, CallKey, CallTree),
                {ok, Res0#{ call_res => aect_call:return_type(InnerCall),
                            call_val => aect_call:return_value(InnerCall),
                            call_gas => aect_call:gas_used(InnerCall) }}
        end,
    {Res, S1}.

ga_meta_tx(PubKey, Spec0, State) ->
    Spec = maps:merge(ga_meta_tx_default(PubKey, State), Spec0),
    {ok, Tx} = aega_meta_tx:new(Spec),
    Tx.

ga_meta_tx_default(PubKey, _State) ->
    #{ fee         => 1000000 * aec_test_utils:min_gas_price()
     , ga_id       => aeser_id:create(account, PubKey)
     , auth_data   => <<"NOT ENCODED ACCORDING TO ABI">>
     , abi_version => aect_test_utils:latest_sophia_abi_version()
     , gas         => 50000
     , gas_price   => 1 * aec_test_utils:min_gas_price()
     , ttl         => 0
     }.

inner_create_tx(Owner, Name, Args, S) ->
    inner_create_tx(Owner, Name, Args, #{}, S).

inner_create_tx(Owner, Name, Args, Options, S) ->
    {ok, #{src := Src, bytecode := Code}} = get_contract(Name),
    CallData = make_calldata(Src, "init", Args),
    Options1 = maps:merge(#{nonce => 0, code => Code, call_data => CallData},
                          maps:without([height, return_return_value, return_gas_used], Options)),
    {create_tx(Owner, Options1, S), S}.

inner_call_tx(Owner, Contract, Name, Fun, Args, S) ->
    inner_call_tx(Owner, Contract, Name, Fun, Args, #{}, S).

inner_call_tx(Caller, Contract, Name, Fun, Args, Options, S) ->
    CallData = make_calldata(Name, Fun, Args),
    Options1 = maps:merge(#{nonce => 0, call_data => CallData},
                          maps:without([height, return_return_value, return_gas_used], Options)),
    {call_tx(Caller, Contract, Options1, S), S}.

%% create_tx(Owner, State) ->
%%     create_tx(Owner, #{}, State).

create_tx(Owner, Spec0, State) ->
    Spec = maps:merge(
        #{ abi_version => aect_test_utils:latest_sophia_abi_version()
         , vm_version  => maps:get(vm_version, Spec0, vm_version())
         , fee         => 100000 * aec_test_utils:min_gas_price()
         , deposit     => 10
         , amount      => 200
         , gas         => 10000 }, Spec0),
    aect_test_utils:create_tx(Owner, Spec, State).

call_tx(Caller, Contract, Spec0, State) ->
    Spec = maps:merge(
        #{ nonce       => 0
         , abi_version => aect_test_utils:latest_sophia_abi_version()
         , fee         => 500000 * aec_test_utils:min_gas_price()
         , amount      => 0
         , gas         => 10000
         }, Spec0),
    aect_test_utils:call_tx(Caller, Contract, Spec, State).


%% compile_contract(Name) ->
%%     aect_test_utils:compile_contract(sophia_version(), lists:concat(["contracts/", Name, ".aes"])).

%% compile_contract_vsn(Name, Vsn) ->
%%     meck:new(aect_sophia, [passthrough]),
%%     meck:expect(aect_sophia, serialize, fun(Map) -> aect_sophia:serialize(Map, Vsn) end),
%%     Res = compile_contract(Name),
%%     meck:unload(aect_sophia),
%%     Res.

%% create_contract(Owner, Name, Args, S) ->
%%     create_contract(Owner, Name, Args, #{}, S).

%% create_contract(Owner, Name, Args, Options, S) ->
%%     case compile_contract(Name) of
%%         {ok, Code} ->
%%             create_contract_with_code(Owner, Code, Args, Options, S);
%%         {error, Reason} ->
%%             error({fail, {error, compile_should_work, got, Reason}})
%%     end.

%% fail_create_contract_with_code(Owner, Code, Args, Options, S) ->
%%     try create_contract_with_code(Owner, Code, Args, Options, S, true) of
%%         _ -> error(succeeded)
%%     catch throw:{ok, R, S1} -> {{error, R}, S1}
%%     end.

%% create_contract_with_code(Owner, Code, Args, Options, S) ->
%%     create_contract_with_code(Owner, Code, Args, Options, S, false).

%% create_contract_with_code(Owner, Code, Args, Options, S, Fail) ->
%%     Nonce       = aect_test_utils:next_nonce(Owner, S),
%%     CallData    = make_calldata_from_code(Code, init, Args),
%%     Options1    = maps:merge(#{nonce => Nonce, code => Code, call_data => CallData},
%%                              maps:without([height, return_return_value, return_gas_used], Options)),
%%     CreateTx    = create_tx(Owner, Options1, S),
%%     Height      = maps:get(height, Options, 1),
%%     PrivKey     = aect_test_utils:priv_key(Owner, S),
%%     S1          = case sign_and_apply_transaction(CreateTx, PrivKey, S, Height) of
%%                       {ok, TmpS} when not Fail -> TmpS;
%%                       {ok,_TmpS} when Fail -> error({error, succeeded});
%%                       {error, R,_TmpS} when not Fail -> error(R);
%%                       {error, R, TmpS} when Fail -> throw({ok, R, TmpS})
%%                   end,
%%     ContractKey = aect_contracts:compute_contract_pubkey(Owner, Nonce),
%%     CallKey     = aect_call:id(Owner, Nonce, ContractKey),
%%     CallTree    = aect_test_utils:calls(S1),
%%     Call        = aect_call_state_tree:get_call(ContractKey, CallKey, CallTree),
%%     Result0     = ContractKey,
%%     Result1     =
%%         case maps:get(return_return_value, Options, false) of
%%             false -> Result0;
%%             true  -> {Result0, {aect_call:return_type(Call), aect_call:return_value(Call)}}
%%         end,
%%     case maps:get(return_gas_used, Options, false) of
%%         false -> {{ok, Result1}, S1};
%%         true  -> {{ok, Result1, aect_call:gas_used(Call)}, S1}
%%     end.

%% call_contract(Caller, ContractKey, Fun, Type, Args, S) ->
%%     call_contract(Caller, ContractKey, Fun, Type, Args, #{}, S).

%% call_contract(Caller, ContractKey, Fun, Type, Args, Options, S) ->
%%     Calldata = make_calldata_from_id(ContractKey, Fun, Args, S),
%%     call_contract_with_calldata(Caller, ContractKey, Type, Calldata, Options, S).

%% call_contract_with_calldata(Caller, ContractKey, Type, Calldata, Options, S) ->
%%     Nonce    = aect_test_utils:next_nonce(Caller, S),
%%     CallTx   = aect_test_utils:call_tx(Caller, ContractKey,
%%                 maps:merge(
%%                 #{ nonce       => Nonce
%%                  , abi_version => aect_test_utils:latest_sophia_abi_version()
%%                  , call_data   => Calldata
%%                  , fee         => maps:get(fee, Options, 1000000 * aec_test_utils:min_gas_price())
%%                  , amount      => 0
%%                  , gas         => 140000
%%                  }, maps:without([height, return_gas_used, return_logs], Options)), S),
%%     Height   = maps:get(height, Options, 1),
%%     PrivKey  = aect_test_utils:priv_key(Caller, S),
%%     case sign_and_apply_transaction(CallTx, PrivKey, S, Height) of
%%         {ok, S1} ->
%%             CallKey  = aect_call:id(Caller, Nonce, ContractKey),
%%             CallTree = aect_test_utils:calls(S1),
%%             Call     = aect_call_state_tree:get_call(ContractKey, CallKey, CallTree),
%%             Result   =
%%                 case aect_call:return_type(Call) of
%%                     ok     -> {ok, Res} = aeso_heap:from_binary(Type, aect_call:return_value(Call)),
%%                               Res;
%%                     error  -> {error, aect_call:return_value(Call)};
%%                     revert -> revert
%%                 end,
%%             Result1 = case maps:get(return_logs, Options, false) of
%%                         true -> {Result, aect_call:log(Call)};
%%                         false -> Result end,
%%             case maps:get(return_gas_used, Options, false) of
%%                 false -> {Result1, S1};
%%                 true  -> {{Result1, aect_call:gas_used(Call)}, S1}
%%             end;
%%         {error, R, S1} ->
%%             {{error, R}, S1}
%%     end.

account_balance(PubKey, S) ->
    Account = aect_test_utils:get_account(PubKey, S),
    {aec_accounts:balance(Account), S}.

%% make_calldata_raw(<<FunHashInt:256>>, Args0) ->
%%     Args = translate_pubkeys(if is_tuple(Args0) -> Args0; true -> {Args0} end),
%%     aeso_heap:to_binary({FunHashInt, Args}).

%% make_calldata_from_code(Code, Fun, Args) when is_atom(Fun) ->
%%     make_calldata_from_code(Code, atom_to_binary(Fun, latin1), Args);
%% make_calldata_from_code(Code, Fun, Args) when is_list(Fun) ->
%%     make_calldata_from_code(Code, list_to_binary(Fun), Args);
%% make_calldata_from_code(Code, Fun, Args) when is_binary(Fun) ->
%%     #{type_info := TypeInfo} = aect_sophia:deserialize(Code),
%%     case aeso_abi:type_hash_from_function_name(Fun, TypeInfo) of
%%         {ok, TypeHash} -> make_calldata_raw(TypeHash, Args);
%%         {error, _} = Err -> error({bad_function, Fun, Err})
%%     end.

%% make_calldata_from_id(Id, Fun, Args, State) ->
%%     {{value, C}, _S} = lookup_contract_by_id(Id, State),
%%     make_calldata_from_code(aect_contracts:code(C), Fun, Args).

make_calldata(Name, Fun, Args) when length(Name) < 20 ->
    {ok, #{src := Src}} = get_contract(Name),
    make_calldata(Src, Fun, Args);
make_calldata(Code, Fun, Args) ->
    {ok, Calldata, _, _} = aeso_compiler:create_calldata(Code, Fun, Args),
    Calldata.

get_contract(Name0) ->
    Name = filename:join("contracts", Name0),
    {ok, Serial} = aect_test_utils:compile_contract(sophia_version(), Name),
    {ok, BinSrc} = aect_test_utils:read_contract(Name),
    {ok, #{ bytecode => Serial, map => aect_sophia:deserialize(Serial),
            src => binary_to_list(BinSrc), bin_src => BinSrc }}.

decode_call_result(Name0, Fun, Type, Val) ->
    Name = filename:join("contracts", Name0),
    {ok, BinSrc} = aect_test_utils:read_contract(Name),
    {ok, AST} = aeso_compiler:to_sophia_value(binary_to_list(BinSrc), Fun, Type, Val),
    prettypr:format(aeso_pretty:expr(AST)).

%% translate_pubkeys(<<N:256>>) -> N;
%% translate_pubkeys([H|T]) ->
%%   [translate_pubkeys(H) | translate_pubkeys(T)];
%% translate_pubkeys(T) when is_tuple(T) ->
%%   list_to_tuple(translate_pubkeys(tuple_to_list(T)));
%% translate_pubkeys(M) when is_map(M) ->
%%   maps:from_list(translate_pubkeys(maps:to_list(M)));
%% translate_pubkeys(X) -> X.

%%%===================================================================
%%% Store
%%%===================================================================

%% store_from_map(Map) ->
%%     maps:fold(fun aect_contracts_store:put/3,
%%               aect_contracts_store:new(), Map).

%% set_ct_store(Map, Ct) ->
%%     aect_contracts:set_state(store_from_map(Map), Ct).

%% get_ct_store(Ct) ->
%%     aect_contracts_store:contents(aect_contracts:state(Ct)).

%% create_store(_Cfg) ->
%%     state(aect_test_utils:new_state()),
%%     Acc1  = ?call(new_account, 100 * aec_test_utils:min_gas_price()),
%%     Ct1   = ?call(insert_contract, Acc1, <<"Code for C1">>),
%%     Ct1   = ?call(get_contract, Ct1),
%%     Empty = #{},
%%     Empty = get_ct_store(Ct1),
%%     ok.

%% read_store(_Cfg) ->
%%     state(aect_test_utils:new_state()),
%%     Acc1   = ?call(new_account, 100 * aec_test_utils:min_gas_price()),
%%     Ct1    = ?call(insert_contract, Acc1, <<"Code for C1">>),
%%     Ct1    = ?call(get_contract, Ct1),
%%     Store1 = #{ <<0>> => <<42>> },
%%     Ct2    = set_ct_store(Store1, Ct1),
%%     Ct2    = ?call(enter_contract, Ct2),
%%     Ct3    = ?call(get_contract, Ct2),
%%     Store1 = get_ct_store(Ct3),
%%     ok.


%% store_zero_value(_Cfg) ->
%%     state(aect_test_utils:new_state()),
%%     Acc1   = ?call(new_account, 100 * aec_test_utils:min_gas_price()),
%%     Ct1    = ?call(insert_contract, Acc1, <<"Code for C1">>),
%%     Ct1    = ?call(get_contract, Ct1),
%%     Store1 = #{ <<0>> => <<42>>
%%               , <<1>> => <<0>>
%%               , <<2>> => <<>> },
%%     Ct2    = set_ct_store(Store1, Ct1),
%%     Ct2    = ?call(enter_contract, Ct2),
%%     %% Empty values are removed in state tree.
%%     Ct3    = ?call(get_contract, Ct2),
%%     Store2 = #{ <<0>> => <<42>>
%%               , <<1>> => <<0>>},
%%     Store2 = get_ct_store(Ct3),
%%     ok.

%% merge_new_zero_value(_Cfg) ->
%%     state(aect_test_utils:new_state()),
%%     Acc1   = ?call(new_account, 100 * aec_test_utils:min_gas_price()),
%%     Ct1    = ?call(insert_contract, Acc1, <<"Code for C1">>),
%%     Ct1    = ?call(get_contract, Ct1),
%%     Store1 = #{ <<0>> => <<42>>
%%               , <<1>> => <<0>>
%%               , <<2>> => <<>> },
%%     Ct2    = set_ct_store(Store1, Ct1),
%%     Ct2    = ?call(enter_contract, Ct2),
%%     %% Empty values are removed in state tree.
%%     Ct3    = ?call(get_contract, Ct2),
%%     Store2 = #{ <<0>> => <<0>>
%%               , <<1>> => <<>>
%%               , <<2>> => <<42>> },
%%     Ct4    = set_ct_store(Store2, Ct3),
%%     Ct4    = ?call(enter_contract, Ct4),
%%     Ct5    = ?call(get_contract, Ct4),
%%     Store3 = #{ <<0>> => <<0>>
%%               , <<2>> => <<42>>},
%%     Store3 = get_ct_store(Ct5),
%%     ok.


%% enter_contract(Contract, S) ->
%%     Contracts = aect_state_tree:enter_contract(Contract, aect_test_utils:contracts(S)),
%%     {Contract, aect_test_utils:set_contracts(Contracts, S)}.

