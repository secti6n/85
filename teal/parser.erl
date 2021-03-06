-module(parser).

-export([test/0]).


term_to_list({term, F, A}) ->
    [F|A];
term_to_list(Atom) when is_atom(Atom) ->
    [Atom].

pred_name(F, A) ->
    list_to_atom(atom_to_list(F) ++ "/" ++ integer_to_list(length(A))).

term_to_query(Term) ->
    [F|A] = term_to_list(Term),
    {pred_name(F,A), A}.

rules(Name) ->
    Filename = filename:join(filename:dirname(code:which(?MODULE)), Name),
    {ok, Bin} = file:read_file(Filename),

    lists:foldl(
      fun ({clause, Head, Body}, Map) ->
              [F|A] = term_to_list(Head),
              Key = pred_name(F,A),
              Value =
                  lists:append(
                    maps:get(Key, Map, []),
                    [{rule, term_to_query(Head),
                      [term_to_query(T) || T <- Body]}]
                   ),
              maps:put(Key, Value, Map)
      end,
      #{},
      rule_parser:parse(Bin)).


symbols(Name) ->
    Filename = filename:join(filename:dirname(code:which(?MODULE)), Name),
    {ok, Bin} = file:read_file(Filename),
    Symbols =
        [ {K, unify:alpha(V)}
          || {K,V} <- symbol_parser:parse(Bin)],
    trie:from_list(Symbols).



add_table(I, #{states := States}, Table, Symbols) ->
    case maps:is_key('symbol/2', maps:get(I, States, #{})) of
        true ->
            [{I,Symbols}|Table];
        false ->
            Table
    end.


complete(Chart = #{states := States}, I, Name, N, {Entry, Count}) ->
    lists:foldl(
      fun ({A, Body, S, Next, I1, Head = {F1,A1}}, C) ->
              Next1 = Next + Count,
              case unify:unify(A, unify:offset(Entry, Next), S) of
                  false ->
                      C;
                  S1 ->
                      case Body of
                          [] ->
                              A2 = unify:alpha(unify:subst(A1, S1)),
                              case chart:add_result(C, I1, F1, A2) of
                                  {ok, C1} ->
                                      complete(C1, I, F1, I1, A2);
                                  {existed, C1} ->
                                      C1
                              end;
                          [{F2,A2}|Body1] ->
                              chart:add_state(C, I+1, F2, {A2, Body1, S1, Next1, I1, Head})
                      end
              end
      end,
      Chart,
      maps:get(Name, maps:get(N, States, #{}), [])).


parse(I, [], Chart, _Tables, _Symbols) ->
    complete(Chart, I, 'eof/0', I, {[], 0});
parse(I, [H|T], Chart, Tables, Symbols) ->
    Tables1 = add_table(I, Chart, Tables, Symbols),

    Tables2 =
        [ {N,maps:get(H,Table)}
          || {N,Table} <- Tables1,
             maps:is_key(H, Table)],

    Entries =
        [ {N, Entry}
          || {N,Table} <- Tables2,
             Entry <- maps:get([],Table,[])],

    Chart1 =
        lists:foldl(
          fun ({N, Entry}, C) ->
                  complete(C, I, 'symbol/2', N, Entry)
          end,
          Chart,
          Entries),

    Tables3 =
        [ {N,Table}
          || {N,Table} <- Tables2,
             maps:size(Table) > 0],

    parse(I+1, T, Chart1, Tables3, Symbols).

parse(List, Grammar, Symbols) ->
    Root = 'root/2',
    #{results := Results} = parse(0, List, chart:new(Root, Grammar), [], Symbols),
    [ {term, root, Term} || {Term, _} <- maps:get(Root, maps:get(0, Results, #{}), [])].


format({tuple, Name, List}) ->
    io_lib:format("~s{~s}", [Name, format_list(List)]);
format({term, Name, List}) ->
    io_lib:format("~s(~s)", [Name, format_list(List)]);
format({var, Name}) ->
    io_lib:format("~s", [Name]);
format(Atom) when is_atom(Atom) ->
    io_lib:format("~s", [Atom]).

format_list(List) ->
    string:join([format(T) || T <- List], ",").

test(List, Rules, Symbols) ->
    Results = parse(List, Rules, Symbols),
    io:format("~ts:~n~s~n", [List, string:join([format(A) || A <- Results], "\n")]).

test(Rules, Symbols) ->
    Strings =
        [
          "各减平均各自乘相加除以项数开方"
        ],
    [test(S, Rules, Symbols) || S <- Strings],
    ok.

test() ->
    test(rules("RULES"), symbols("SYMBOLS")).
