using Anthropic
using Anthropic: process_stream
using Test

# Create a long prompt by repeating text
base_text = "This is a long text that we'll repeat multiple times to ensure we hit the 2000 character threshold for caching. " * 
            "We want to make sure we have enough content to trigger the caching mechanism properly. " * 
            "The cache will help reduce costs and improve response times for repeated content. "
long_prompt = """
    Random number: $(rand()) to make text unique. 
    $(repeat(base_text, 20))

    Only answer with a yes.
"""

@testset "Cache Functionality Tests" begin
    let
        # Store metadata for verification in local scope
        first_user_meta = Ref{Dict{String,Any}}()
        first_ai_meta = Ref{Dict{String,Any}}()
        second_user_meta = Ref{Dict{String,Any}}()
        second_ai_meta = Ref{Dict{String,Any}}()
        full_response = ""

        # First request - should create cache
        @testset "Initial Request" begin
            channel = stream_response([Dict("role" => "user", "content" => long_prompt)]; 
                model="claude-3-5-sonnet-20241022", cache=:all, printout=false)

            full_response = process_stream(channel;
                on_meta_usr = meta -> (first_user_meta[] = meta),
                on_meta_ai = (meta, _) -> (first_ai_meta[] = meta),
                on_text = _ -> nothing
            )

            # Test input tokens presence
            @test haskey(first_user_meta[], "input_tokens")
            @test haskey(first_user_meta[], "cache_creation_input_tokens")
            
            # Test cache creation behavior
            @test get(first_user_meta[], "cache_creation_input_tokens", 0) > 0
            @test get(first_user_meta[], "cache_read_input_tokens", 0) == 0
            
            # Test response content
            @test lowercase(strip(full_response)) == "yes"
        end

        # Second request - should use cache
        @testset "Cached Request" begin
            channel = stream_response([
                Dict("role" => "user", "content" => long_prompt),
                Dict("role" => "assistant", "content" => full_response),
                Dict("role" => "user", "content" => "Random number: $(rand()) to make text unique. " * long_prompt)
            ]; model="claude-3-5-sonnet-20241022", cache=:all_but_last, printout=false)

            second_response = process_stream(channel;
                on_meta_usr = meta -> (second_user_meta[] = meta),
                on_meta_ai = (meta, _) -> (second_ai_meta[] = meta),
                on_text = _ -> nothing
            )

            # Test metadata presence
            @test haskey(second_user_meta[], "input_tokens")
            
            # Test cache usage behavior
            @test get(second_user_meta[], "cache_read_input_tokens", 0) > 0
            @test get(second_user_meta[], "cache_creation_input_tokens", 0) == 0
            
            # Test response and performance
            @test lowercase(strip(second_response)) == "yes"
            # timingwise things might not be consistent so we won't use it now.
            # @test second_user_meta[]["elapsed"] < first_user_meta[]["elapsed"]
        end

        # Print detailed cache metrics for debugging
        @testset "Cache Metrics" begin
            # Test relative token counts
            @test get(first_user_meta[], "cache_creation_input_tokens", 0) > 
                  get(second_user_meta[], "cache_creation_input_tokens", 0)
            @test get(first_user_meta[], "cache_read_input_tokens", 0) < 
                  get(second_user_meta[], "cache_read_input_tokens", 0)
            
            # Print metrics for visibility
            println("\nCache Metrics:")
            println("First request cache creation tokens: ", get(first_user_meta[], "cache_creation_input_tokens", 0))
            println("Second request cache read tokens: ", get(second_user_meta[], "cache_read_input_tokens", 0))
        end
    end
end
