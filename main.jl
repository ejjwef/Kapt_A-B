# ==========================================
# MAIN EXECUTION SCRIPT
# ==========================================

include("data_preparation.jl") 

using Graphs

function test_pipeline()
    println("--- Starting Orange Challenge Pipeline ---")
    
    instance_name = "setA-01"
    println("Loading data for $instance_name...")
    
    # Unpack all 6 variables!
    net, demands, max_segments, budget_t1, r0, r1 = prepare_data(instance_name)
    
    println("✓ Data loaded successfully!")
    println("  - Vertices: ", nv(net.graph))
    println("  - Edges: ", ne(net.graph))
    println("  - Total Demands: ", length(demands))
    println("  - Max Segments: ", max_segments)
    println("  - Budget for t=1: ", budget_t1)
    println("  - Computed r0 entries: ", length(r0))
    println("  - Computed r1 entries: ", length(r1))
end

test_pipeline()