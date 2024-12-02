using RelevanceStacktrace
using Anthropic

# Get the raw stream
channel = stream_response("Tell me a short joke", printout=true)

# Process the stream
using Anthropic:process_stream
full_response = process_stream(channel)

println()
println("Full response: ", full_response)
# println("Message metadata: ", message_meta)

# # Additional debug information
# println("\nRaw stream data:")
# for (i, chunk) in enumerate(Anthropic.stream_response("Tell me a short joke", printout=false))
#     println("Chunk $i:")
#     println(chunk)
# end
