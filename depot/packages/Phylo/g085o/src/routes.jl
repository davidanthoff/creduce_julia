using Compat: mapreduce
function _treepast(tree::T, node::NL) where {NL, BL, T <: AbstractTree{NL, BL}}
    branches = BL[]
    nodes = NL[node]
    while hasinbound(tree, node)
        inbound = getinbound(tree, node)
        branches = push!(branches, inbound)
        node = src(tree, inbound)
        nodes = push!(nodes, node)
    end
    return branches, nodes
end
function _treefuture(tree::T, node::NL) where {NL, BL, T <: AbstractTree{NL, BL}}
    branches = BL[]
    nodestoprocess = NL[node]
    nodesprocessed = NL[]
    while !isempty(nodestoprocess)
        nextnode = pop!(nodestoprocess)
        push!(nodesprocessed, nextnode)
        outbounds = getoutbounds(tree, nextnode)
        append!(branches, outbounds)
        children = map(branch -> dst(tree, branch), outbounds)
        append!(nodestoprocess, children)
    end
    return branches, nodesprocessed
end
""" """ function branchhistory(tree::T, node::NL) where {NL, BL, T <: AbstractTree{NL, BL}}
    return _treepast(tree, node)[1]
end
""" """ function nodehistory(tree::T, node::NL) where {NL, BL, T <: AbstractTree{NL, BL}}
    return _treepast(tree, node)[2]
end
""" """ function branchroute(tree::T, node1::NL, node2::NL) where {NL, BL, T <: AbstractTree{NL, BL}}
    branches1, nodes1 = _treepast(tree, node1)
    branches2, nodes2 = _treepast(tree, node2)
    nodes1[end] == nodes2[end] ||
        return error("No route between nodes")
    common = branches1 ∩ branches2
    return append!(filter(b -> b ∉ common, branches1),
                   filter(b -> b ∉ common, reverse(branches2)))
end
""" """ function noderoute(tree::T, node1::NL, node2::NL) where {NL, BL, T <: AbstractTree{NL, BL}}
    branches1, nodes1 = _treepast(tree, node1)
    branches2, nodes2 = _treepast(tree, node2)
    nodes1[end] == nodes2[end] ||
        return error("No route between nodes")
    common = nodes1[end]
    while min(length(nodes1), length(nodes2)) > 0 && nodes1[end] == nodes2[end]
        common = nodes1[end]
        pop!(nodes1)
        pop!(nodes2)
    end
    push!(nodes1, common)
    return append!(nodes1, reverse(nodes2))
end
""" """ function distance(tree::AbstractTree, node1, node2)
    branches = branchroute(tree, node1, node2)
    return mapreduce(branch -> getlength(tree, branch), +, branches;
    init = 0.0)
end
""" """ function distances(tree::AbstractTree)
    leaves = nodenamefilter(isleaf, tree)
    return [distance(tree, i, j) for i in leaves, j in leaves]
end
""" """ function heighttoroot(tree::AbstractTree, node)
    return mapreduce(branch -> getlength(tree, branch), +,
                     branchhistory(tree, node); init = 0.0)
end
""" """ function heightstoroot(tree::AbstractTree)
    return [heighttoroot(tree, i) for i in nodenamefilter(isleaf, tree)]
end
