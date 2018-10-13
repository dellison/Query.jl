"""
    @select(args...)
Select columns from a table using commands in order.
```
julia> df = (foo=[1,2,3], bar=[3.0,2.0,1.0], bat=["a","b","c"]) |> DataFrame
3×3 DataFrame
│ Row │ foo   │ bar     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 3.0     │ a      │
│ 2   │ 2     │ 2.0     │ b      │
│ 3   │ 3     │ 1.0     │ c      │

julia> df |> Query.@select(startswith(:b), -:bar) |> DataFrame
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
    foo = :_
    for arg in args
        if typeof(arg) == QuoteNode
            # select
            foo = :( select($foo, Val($(arg))) )
        else
            arg = string(arg)
            # remove
            m1 = match(r"^-:(.+)", arg)
            #TODO: variable case
            # single-parameter functions
            m2 = match(r"^(startswith|endswith|occursin)\(\"(.+)\"\)", arg)
            # dual-parameter functions
            m3 = match(r"^(rangeat)\(:([^,]+), *:([^,]+)\)", arg)
            if m1 !== nothing
                foo = :( remove($foo, Val($(QuoteNode(Symbol(m1[1]))))) )
            elseif m2 !== nothing
                if m2[1] == "startswith"
                    foo = :( startswith($foo, Val($(QuoteNode(Symbol(m2[2]))))) )
                elseif m2[1] == "endswith"
                    foo = :( endswith($foo, Val($(QuoteNode(Symbol(m2[2]))))) )
                elseif m2[1] == "occursin"
                    foo = :( occursin($foo, Val($(QuoteNode(Symbol(m2[2]))))) )
                end
            elseif m3 !== nothing
                if m3[1] == "rangeat"
                    foo = :( range($foo, Val($(QuoteNode(Symbol(m3[2])))), Val($(QuoteNode(Symbol(m3[3]))))) )
                end
            end
        end
    end
    return :(Query.@map( $foo ) )
end

"""
    @rename(args...)
Replace column names in a table with new given names.
```
julia> df = (foo=[1,2,3], bar=[3.0,2.0,1.0], bat=["a","b","c"]) |> DataFrame
3×3 DataFrame
│ Row │ foo   │ bar     │ bat    │
│     │ Int64 │ Float64 │ String │
├─────┼───────┼─────────┼────────┤
│ 1   │ 1     │ 3.0     │ a      │
│ 2   │ 2     │ 2.0     │ b      │
│ 3   │ 3     │ 1.0     │ c      │

julia> df |> Query.@rename(foo = fat, bar = ban) |> DataFrame
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
    foo = :_
    for arg in args
        name, replace = split(string(arg), " = ")
        foo = :( Query.rename($foo, Val($(QuoteNode(Symbol(name)))), Val($(QuoteNode(Symbol(replace))))) )
    end
    return :(Query.@map( $foo ) )
end


macro mutate(args...)
    foo = :_
    for arg in args

    end
end

# Optimize
@generated function select(a::NamedTuple{an}, ::Val{bn}) where {an, bn}
    names = ((i for i in an if i == bn)...,)
    types = Tuple{(fieldtype(a, n) for n in names)...}
    vals = Expr[:(getfield(a, $(QuoteNode(n)))) for n in names]
    return :(NamedTuple{$names,$types}(($(vals...),)))
end

@generated function remove(a::NamedTuple{an}, ::Val{bn}) where {an, bn}
    names = ((i for i in an if i != bn)...,)
    types = Tuple{(fieldtype(a, n) for n in names)...}
    vals = Expr[:(getfield(a, $(QuoteNode(n)))) for n in names]
    return :(NamedTuple{$names,$types}(($(vals...),)))
end

@generated function Base.startswith(a::NamedTuple{an}, ::Val{bn}) where {an, bn}
    names = ((i for i in an if startswith(String(i), String(bn)))...,)
    types = Tuple{(fieldtype(a, n) for n in names)...}
    vals = Expr[:(getfield(a, $(QuoteNode(n)))) for n in names]
    return :(NamedTuple{$names,$types}(($(vals...),)))
end

@generated function Base.endswith(a::NamedTuple{an}, ::Val{bn}) where {an, bn}
    names = ((i for i in an if endswith(String(i), String(bn)))...,)
    types = Tuple{(fieldtype(a, n) for n in names)...}
    vals = Expr[:(getfield(a, $(QuoteNode(n)))) for n in names]
    return :(NamedTuple{$names,$types}(($(vals...),)))
end

@generated function Base.occursin(a::NamedTuple{an}, ::Val{bn}) where {an, bn}
    names = ((i for i in an if occursin(String(bn), String(i)))...,)
    types = Tuple{(fieldtype(a, n) for n in names)...}
    vals = Expr[:(getfield(a, $(QuoteNode(n)))) for n in names]
    return :(NamedTuple{$names,$types}(($(vals...),)))
end

@generated function rename(a::NamedTuple{an}, ::Val{bn}, ::Val{cn}) where {an, bn, cn}
    names = Symbol[]
    typesArray = DataType[]
    vals = Expr[]
    for n in an
        if n == bn
            push!(names, cn)
        else
            push!(names, n)
        end
        push!(typesArray, fieldtype(a, n))
        push!(vals, :(getfield(a, $(QuoteNode(n)))))
    end
    types = Tuple{typesArray...}
    return :(NamedTuple{$(names...,),$types}(($(vals...),)))
end

@generated function Base.range(a::NamedTuple{an}, ::Val{bn}, ::Val{cn}) where {an, bn, cn}
    rangeStarted = false
    names = Symbol[]
    for n in an
        if n == bn
            rangeStarted = true
        end
        if rangeStarted
            push!(names, n)
        end
        if n == cn
            rangeStarted = false
            break
        end
    end
    types = Tuple{(fieldtype(a, n) for n in names)...}
    vals = Expr[:(getfield(a, $(QuoteNode(n)))) for n in names]
    return :(NamedTuple{$(names...,),$types}(($(vals...),)))
end