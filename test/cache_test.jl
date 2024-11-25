using Anthropic
using Anthropic: process_stream

# Create a long prompt by repeating text
base_text = "This is a long text that we'll repeat multiple times to ensure we hit the 2000 character threshold for caching. " * 
            "We want to make sure we have enough content to trigger the caching mechanism properly. " * 
            "The cache will help reduce costs and improve response times for repeated content. "
long_prompt = repeat(base_text, 20) * "\n\nOnly answer with a yes."

# First message with caching enabled
println("\nFirst request (should create cache):")
channel = stream_response([Dict("role" => "user", "content" => long_prompt)]; 
    model="claude-3-5-sonnet-20241022", cache=:all, printout=false)

full_response = process_stream(channel;
    on_meta_usr = meta -> println("User meta: ", Anthropic.format_meta_info(meta)),
    on_meta_ai = (meta, _) -> println("AI meta: ", Anthropic.format_meta_info(meta)),
    on_text = print
)
@show full_response

println()

# Second request with same prompt (should use cache)
println("\nSecond request (should use cache):")
channel = stream_response([
    Dict("role" => "user", "content" => long_prompt),
    Dict("role" => "assistant", "content" => full_response),
    Dict("role" => "user", "content" => "ok3 " * long_prompt)
]; model="claude-3-5-sonnet-20241022", cache=:all_but_last, printout=false)

process_stream(channel;
    on_meta_usr = meta -> println("User meta: ", Anthropic.format_meta_info(meta)),
    on_meta_ai = (meta, _) -> println("AI meta: ", Anthropic.format_meta_info(meta)),
    on_text = print
)
