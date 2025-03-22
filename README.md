## Anthropic.jl

Anthropic.jl is a Julia package that provides a simple interface to interact with Anthropic's AI models, particularly Claude. 
Now it will become deprecared as [PromptingTools.jl](https://github.com/svilupp/PromptingTools.jl) also support streaming. But of course it is lot more complicated than this project, so hopefully some day we will also simplify the PromptingTools.jl as time goes. ;)

## Features
- Stream responses from Anthropic's AI models
- Safe API calls with automatic retries for server errors

## Installation

```julia
] add Anthropic
```

## Usage

Here's a quick example of how to use Anthropic.jl:

```julia
using Anthropic

# Set your API key as an environment variable or like this
ENV["ANTHROPIC_API_KEY"] = "your_api_key_here"


# Get the raw stream
channel = stream_response("Tell me a short joke", printout=false)

# Process the stream
using Anthropic:process_stream
full_response, message_meta = process_stream(channel)

# Stream a response called with protection.
response_channel = ai_stream_safe("Tell me a joke", model="claude-3-opus-20240229")
response_channel = ai_stream_safe([Dict("role" => "user", "content" => "Tell me a joke")], model="claude-3-opus-20240229", max_tokens=100)


for chunk in response_channel
	print("\e[36m$chunk \e[0m") # Print the streamed response
end

# Or use the non-streaming version which is a wrapper of the ai_generate from promptingtools.
response = ai_ask_safe("What's the capital of France?", model="claude-3-opus-20240229")
println(response.content)
```

## Comprehensive example (Streaming)

Please see file [LLM_solve.jl](https://github.com/Sixzero/EasyContext.jl/blob/master/src/transform/LLM_solve.jl): 
So something like:
```julia
include("syntax_highlight.jl")

function LLM_solve(conv, cache; model::String="claude-3-5-sonnet-20241022", on_meta_usr=noop, on_text=noop, on_meta_ai=noop, on_error=noop, on_done=noop, on_start=noop)
    channel = ai_stream(conv, model=model, printout=false, cache=cache)
    highlight_state = SyntaxHighlightState()

    try
        process_stream(channel; 
                on_text     = text -> (on_text(text); handle_text(highlight_state, text)),
                on_meta_usr = meta -> (flush_highlight(highlight_state); on_meta_usr(meta); print_user_message(meta)),
                on_meta_ai  = (meta, full_msg) -> (flush_highlight(highlight_state); on_meta_ai(create_AI_message(full_msg, meta)); print_ai_message(meta)),
                on_error,
                on_done     = () -> (flush_highlight(highlight_state); on_done()),
                on_start)
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        return e
    end
end

# Helper functions
flush_highlight(state) = process_buffer(state, flush=true)
print_user_message(meta) = println("\e[32mUser message: \e[0m$(Anthropic.format_meta_info(meta))\n\e[36m¬ \e[0m")
print_ai_message(meta) = println("\n\e[32mAI message: \e[0m$(Anthropic.format_meta_info(meta))")
```
This write out close to every data for you (text/prices/tokens/caching).   

## TODO

- [x] Caching support
- [x] Image support
- [x] Token, cost and elapsed time should be also noted
- [x] Type ERROR in the streaming should be handled more comprehensively...
- [ ] Cancel request works on the web... (maybe it is only working for completion API?)

### Response Cancellation Implementation
Implement response cancellation functionality. Canceling a query should be possible somehow! 

**Stop API Example:**
```
https://api.claude.ai/api/organizations/d9192fb1-1546-491e-89f2-d3432c9695d2/chat_conversations/f2f779eb-49c5-4605-b8a5-009cdb88fe20/stop_response
https://api.claude.ai/api/organizations/d9192fb1-1546-491e-89f2-d3432c9695d2/chat_conversations/c05a216d-952c-4fb4-8797-c6442a3a13af/stop_response
```

### Other Case
**Chat Conversation ID:**
```
https://api.claude.ai/api/organizations/d9192fb1-1546-491e-89f2-d3432c9695d2/chat_conversations
```

**Response:**
```json
{
    "uuid": "500aece9-8e42-498e-a035-5840e25f8864",
    "name": "",
    "summary": "",
    "model": null,
    "created_at": "2024-08-11T20:59:19.722850Z",
    "updated_at": "2024-08-11T20:59:19.722850Z",
    "settings": {
        "preview_feature_uses_artifacts": true,
        "preview_feature_uses_latex": null,
        "preview_feature_uses_citations": null
    },
    "is_starred": false,
    "project_uuid": null,
    "current_leaf_message_uuid": null
}
```

### Future Improvements
- Add support for more Anthropic API features

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
