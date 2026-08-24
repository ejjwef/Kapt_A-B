using JSON3
using Graphs

struct NetworkData
    graph::SimpleDiGraph
    json_to_vertex::Dict{Int, Int}
    vertex_to_json::Dict{Int, Int}
    metrics::Dict{Tuple{Int, Int}, Float64}
    capacities::Dict{Tuple{Int, Int}, Float64}
    edge_ids::Dict{Int, Tuple{Int, Int}} 
end

# 1. Map JSON IDs and build the graph
function load_network(net_json_path::String)
    data = JSON3.read(read(net_json_path, String))
    
    n = length(data.nodes)
    g = SimpleDiGraph(n)
    
    json_to_vertex = Dict{Int, Int}()
    vertex_to_json = Dict{Int, Int}()
    metrics = Dict{Tuple{Int, Int}, Float64}()
    capacities = Dict{Tuple{Int, Int}, Float64}()
    edge_ids = Dict{Int, Tuple{Int, Int}}() 
    
    for (v, node) in enumerate(data.nodes)
        id = Int(node.id)
        json_to_vertex[id] = v
        vertex_to_json[v] = id
    end
    
    for link in data.links
        from_id = Int(link.from)
        to_id = Int(link.to)
        
        u = json_to_vertex[from_id]
        v = json_to_vertex[to_id]
        
        add_edge!(g, u, v)
        
        metrics[(u, v)] = Float64(link.metric)
        capacities[(u, v)] = Float64(link.capacity)
        
        # Storing the link ID so we can remove it later for t=1
        edge_ids[Int(link.id)] = (u, v)
    end
    
    return NetworkData(g, json_to_vertex, vertex_to_json, metrics, capacities, edge_ids)
end

# 2. Build the distance matrix for Dijkstra
function metric_matrix(net::NetworkData)
    n = nv(net.graph)
    D = fill(Inf, n, n)
    
    for v in vertices(net.graph)
        D[v, v] = 0.0
    end
    
    for e in edges(net.graph)
        u, v = src(e), dst(e)
        D[u, v] = net.metrics[(u, v)]
    end
    
    return D
end

# 3. Load traffic demands
function load_demands(tm_json_path::String, net::NetworkData)
    data = JSON3.read(read(tm_json_path, String))
    demands = []
    for d in data.demands
        s = net.json_to_vertex[Int(d.s)]
        t = net.json_to_vertex[Int(d.t)]
        push!(demands, (s=s, t=t, v0=Float64(d.v[1]), v1=Float64(d.v[2])))
    end
    return demands
end

# 4. Load max segments
function load_scenario(scenario_json_path::String)
    data = JSON3.read(read(scenario_json_path, String))
    max_segments = Int(data.max_segments)
    
    budget_t1 = length(data.budget) > 0 ? Int(data.budget[1].value) : 0
    failed_links = Int[]
    
    if length(data.interventions) > 0
        for link_id in data.interventions[1].links
            push!(failed_links, Int(link_id))
        end
    end
    
    return max_segments, budget_t1, failed_links
end

# 5. Calculate all pairs shortest paths
function all_pairs_shortest_data(net::NetworkData, D::Matrix{Float64})
    n = nv(net.graph)
    dist = fill(Inf, n, n)
    sigma = zeros(Float64, n, n) 
    
    for i in 1:n
        state = dijkstra_shortest_paths(net.graph, i, D; allpaths=true)
        for j in 1:n
            dist[i, j] = state.dists[j]
            sigma[i, j] = state.pathcounts[j]
        end
    end
    return dist, sigma
end

# 6. Calculate the split coefficients r(i,j,a,t)
function calculate_r(net::NetworkData, dist::Matrix{Float64}, sigma::Matrix{Float64})
    n = nv(net.graph)
    r = Dict{Tuple{Int, Int, Tuple{Int, Int}}, Float64}()
    
    for i in 1:n
        for j in 1:n
            if i == j || dist[i, j] == Inf
                continue
            end
            
            for e in edges(net.graph)
                u = src(e)
                v = dst(e)
                c_a = net.metrics[(u, v)]
                
                if isapprox(dist[i, u] + c_a + dist[v, j], dist[i, j], atol=1e-7)
                    r[(i, j, (u, v))] = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
                else
                    r[(i, j, (u, v))] = 0.0
                end
            end
        end
    end
    return r
end

# 7. Wrapper function to hand over to Person B
function prepare_data(instance_prefix::String)
    net = load_network("data/" * instance_prefix * "-net.json")
    demands = load_demands("data/" * instance_prefix * "-tm.json", net)
    max_segments, budget_t1, failed_links = load_scenario("data/" * instance_prefix * "-scenario.json")
    
    # Calculate for t = 0
    D0 = metric_matrix(net)
    dist0, sigma0 = all_pairs_shortest_data(net, D0)
    r0 = calculate_r(net, dist0, sigma0)
    
    # Calculate for t = 1 (Degraded Network)
    net_t1 = deepcopy(net)
    for link_id in failed_links
        u, v = net.edge_ids[link_id]
        rem_edge!(net_t1.graph, u, v)
    end
    
    D1 = metric_matrix(net_t1)
    dist1, sigma1 = all_pairs_shortest_data(net_t1, D1)
    r1 = calculate_r(net_t1, dist1, sigma1)
    
    return net, demands, max_segments, budget_t1, r0, r1
end