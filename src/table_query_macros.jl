using QueryOperators

"""
    @select(args...)
Select columns from a table using commands in order.
```
julia> df = DataFrame(foo=[1,2,3], bar=[3.0,2.0,1.0], bat=["a","b","c"])
3×3 DataFrame
│ Row │ foo   │ bar     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 3.0     │ a      │
│ 2   │ 2     │ 2.0     │ b      │
│ 3   │ 3     │ 1.0     │ c      │

julia> df |> @select(startswith("b"), -:bar) |> DataFrame
3×1 DataFrame
│ Row │ bat    │
│     │ String │
├─────┼────────┤
│ 1   │ a      │
│ 2   │ b      │
│ 3   │ c      │
```
"""
macro select(args...)
    prev = NamedTuple()
    for arg in args
        if typeof(arg) == Expr && (string(arg) == "everything()")
            # select everything
            prev = :_
        elseif typeof(arg) == Int
            # select by position
            if arg > 0
                prev = :( merge($prev, QueryOperators.NamedTupleUtilities.select(_, Val(keys(_)[$arg]))) )
            # remove by position
            elseif arg < 0
                sel = ifelse(prev == NamedTuple(), :_, prev)
                prev = :( QueryOperators.NamedTupleUtilities.remove($sel, Val(keys($sel)[-$arg])) )
            end
        elseif typeof(arg) == QuoteNode
            # select by name
            prev = :( merge($prev, QueryOperators.NamedTupleUtilities.select(_, Val($(arg)))) )
        else
            arg = string(arg)
            # select by element type
            m_type = match(r":\(:(.+)\)", arg)
            # remove by name
            m_rem = match(r"^-:(.+)", arg)
            # remove by predicate functions
            m_rem_pred = match(r"^-\(*(startswith|endswith|occursin)\(\"(.+)\"\)+", arg)
            # select by range, with multiple syntaxes supported
            m_range = match(r"^:([^,:]+) *: *:([^,:]+)", arg)
            m_range_ind = match(r"^([0-9]+) *: *([0-9]+)", arg)
            if m_range == nothing && m_range_ind == nothing
                m_range = match(r"^rangeat\(:([^,]+), *:([^,]+)\)", arg)
                m_range_ind = match(r"^rangeat\(([0-9]+), *([0-9]+)\)", arg)
            end
            # select by predicate functions
            m_pred = match(r"^(startswith|endswith|occursin)\(\"(.+)\"\)", arg)
            is_neg_pred = false
            if m_pred == nothing
                m_pred = match(r"^!\(*(startswith|endswith|occursin)\(\"(.+)\"\)+", arg)
                is_neg_pred = true
            end

            # TODO: eltype
            if m_type !== nothing
                prev = :( merge($prev, QueryOperators.NamedTupleUtilities.oftype(_, parse(DataType, @datatype($m_type[1])))) )
            elseif m_rem !== nothing
                prev = ifelse(prev == NamedTuple(), :_, prev)
                prev = :( QueryOperators.NamedTupleUtilities.remove($prev, Val($(QuoteNode(Symbol(m_rem[1]))))) )
            elseif m_rem_pred !== nothing
                prev = ifelse(prev == NamedTuple(), :_, prev)
                if m_rem_pred[1] == "startswith"
                    prev = :( QueryOperators.NamedTupleUtilities.not_startswith($prev, Val($(QuoteNode(Symbol(m_rem_pred[2]))))) )
                elseif m_rem_pred[1] == "endswith"
                    prev = :( QueryOperators.NamedTupleUtilities.not_endswith($prev, Val($(QuoteNode(Symbol(m_rem_pred[2]))))) )
                elseif m_rem_pred[1] == "occursin"
                    prev = :( QueryOperators.NamedTupleUtilities.not_occursin($prev, Val($(QuoteNode(Symbol(m_rem_pred[2]))))) )
                end
            elseif m_range !== nothing || m_range_ind !== nothing
                if m_range_ind !== nothing
                    a = parse(Int, m_range_ind[1])
                    b = parse(Int, m_range_ind[2])
                    prev = :( merge($prev, QueryOperators.NamedTupleUtilities.range(_, Val(keys(_)[$a]), Val(keys(_)[$b]))) )
                else
                    prev = :( merge($prev, QueryOperators.NamedTupleUtilities.range(_, Val($(QuoteNode(Symbol(m_range[1])))), Val($(QuoteNode(Symbol(m_range[2])))))) )
                end
            elseif m_pred !== nothing
                if is_neg_pred == false
                    if m_pred[1] == "startswith"
                        sel = :( QueryOperators.NamedTupleUtilities.startswith(_, Val($(QuoteNode(Symbol(m_pred[2]))))) )
                    elseif m_pred[1] == "endswith"
                        sel = :( QueryOperators.NamedTupleUtilities.endswith(_, Val($(QuoteNode(Symbol(m_pred[2]))))) )
                    elseif m_pred[1] == "occursin"
                        sel = :( QueryOperators.NamedTupleUtilities.occursin(_, Val($(QuoteNode(Symbol(m_pred[2]))))) )
                    end
                else
                    if m_pred[1] == "startswith"
                        sel = :( QueryOperators.NamedTupleUtilities.not_startswith(_, Val($(QuoteNode(Symbol(m_pred[2]))))) )
                    elseif m_pred[1] == "endswith"
                        sel = :( QueryOperators.NamedTupleUtilities.not_endswith(_, Val($(QuoteNode(Symbol(m_pred[2]))))) )
                    elseif m_pred[1] == "occursin"
                        sel = :( QueryOperators.NamedTupleUtilities.not_occursin(_, Val($(QuoteNode(Symbol(m_pred[2]))))) )
                    end
                end
                prev = :( merge($prev, $sel) )
            end
        end
    end

    return :(Query.@map( $prev ) )
end

"""
    @rename(args...)
Replace column names in a table with new given names.
```
julia> df = DataFrame(foo=[1,2,3], bar=[3.0,2.0,1.0], bat=["a","b","c"])
3×3 DataFrame
│ Row │ foo   │ bar     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 3.0     │ a      │
│ 2   │ 2     │ 2.0     │ b      │
│ 3   │ 3     │ 1.0     │ c      │

julia> df |> @rename(:foo => :fat, :bar => :ban) |> DataFrame
3×3 DataFrame
│ Row │ fat   │ ban     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 3.0     │ a      │
│ 2   │ 2     │ 2.0     │ b      │
│ 3   │ 3     │ 1.0     │ c      │
```
"""
macro rename(args...)
    prev = :_
    for arg in args
        n = match(r"^(.+) *=> *:(.+)", string(arg))
        try
            # rename by position
            n1 = parse(Int, n[1])
            n2 = strip(n[2])
            prev = :( QueryOperators.NamedTupleUtilities.rename($prev, Val(keys(_)[$n1]), Val($(QuoteNode(Symbol(n2))))) )
        catch
            # rename by name
            m = match(r"^:(.+) *=> *:(.+)", string(arg))
            m1, m2 = strip(m[1]), strip(m[2])
            if m !== nothing
                prev = :( QueryOperators.NamedTupleUtilities.rename($prev, Val($(QuoteNode(Symbol(m1)))), Val($(QuoteNode(Symbol(m2))))) )
            end
        end
    end
    return :(Query.@map( $prev ) )
end

"""
    @mutate(args...)
Replace all elements in selected columns with specified formulae.
```
julia> df = DataFrame(foo=[1,2,3], bar=[3.0,2.0,1.0], bat=["a","b","c"])
3×3 DataFrame
│ Row │ foo   │ bar     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 3.0     │ a      │
│ 2   │ 2     │ 2.0     │ b      │
│ 3   │ 3     │ 1.0     │ c      │

julia> df |> @mutate(bar = _.foo + 2 * _.bar, bat = "com" * _.bat) |> DataFrame
3×3 DataFrame
│ Row │ foo   │ bar     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 7.0     │ coma   │
│ 2   │ 2     │ 6.0     │ comb   │
│ 3   │ 3     │ 5.0     │ comc   │
```
"""
macro mutate(args...)
    prev = :_
    for arg in args
        prev = :( merge($prev, ($(esc(arg.args[1])) = $(arg.args[2]),)) )
    end
    return :( Query.@map( $prev ) )
end

macro datatype(str)
    :($(Symbol(str)))
end