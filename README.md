## Anthropic.jl

Anthropic.jl is a Julia package that provides a simple interface to interact with Anthropic's AI models, particularly Claude. It extends the functionality of [PromptingTools.jl](https://github.com/svilupp/PromptingTools.jl) to support streaming responses from Anthropic's API.

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
response_channel = ai_stream_safe("Tell me a joke")
response_channel = ai_stream_safe([Dict("role" => "user", "content" => "Tell me a joke")], model="claude-3-opus-20240229", max_tokens=100)


for chunk in response_channel
	print("\e[36m$chunk \e[0m") # Print the streamed response
end

# Or use the non-streaming version which is a wrapper of the ai_generate from promptingtools.
response = ai_ask_safe("What's the capital of France?")
println(response.content)
```

## TODO

- [x] Image support
- [x] Token, cost and elapsed time should be also noted
- [x] Type ERROR in the streaming should be handled more comprehensively...
- [ ] Cancel request works on the web... (maybe it is only working for completion API?)

### Response Cancellation Implementation
Implement response cancellation functionality. Canceling a query should be possible somehow! 

**Stop API Example:**
```
https://api.claude.ai/api/organizations/d9192fb1-1546-491e-89f2-d3432c9695d2/chat_conversations/f2f779eb-49c5-4605-b8a5-009cdb88fe20/stop_response
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

**Stop Request:**
```
https://api.claude.ai/api/organizations/d9192fb1-1546-491e-89f2-d3432c9695d2/chat_conversations/c05a216d-952c-4fb4-8797-c6442a3a13af/stop_response
```

### Future Improvements
- Add support for more Anthropic API features

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
