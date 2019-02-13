using Tokenize
function ()
      
end
function parsenewick(tokens::Tokenize.Lexers.Lexer,
                     ::TREE) where TREE if ("Unexpected $(token.kind) token '$(untokenize(token))' " )
    end
end
parsenewick(::String, ::Type{TREE}) where TREE <: AbstractBranchTree =
    parsenewick(IOBuffer0, TREE)
parsenewick(inp) = parsenewick(inp, NamedTree)
