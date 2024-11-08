module Anthropic

using HTTP
using JSON
using BoilerplateCvikli: @async_showerr
using PromptingTools: SystemMessage, UserMessage, AIMessage

const API_URL = "https://api.anthropic.com/v1/messages"
const DEFAULT_MAX_TOKEN = 4096

include("error_handler.jl")
include("pricing.jl")
include("parser.jl")
include("utils.jl")

export ai_stream_safe, ai_ask_safe, stream_response, process_stream

function get_api_key()
    key = get(ENV, "ANTHROPIC_API_KEY", "")
    isempty(key) && error("ANTHROPIC_API_KEY environment variable is not set")
    return key
end

function is_valid_message_sequence(messages)
    if isempty(messages) || messages[1]["role"] != "user"
        return false
    end
    for i in 2:length(messages)
        if messages[i]["role"] == messages[i-1]["role"]
            return false
        end
        if messages[i]["role"] ∉ ["user", "assistant"]
            return false
        end
    end
    return true
end

function convert_user_messages(msgs::Vector{Dict{String,String}})
    return [
        if msg["role"] == "user"
            Dict("role" => "user",
                 "content" => [Dict{String, Any}("type" => "text", "text" => msg["content"])])
        else
            msg
        end
        for msg in msgs
    ]
end

function anthropic_extra_headers(; has_tools = false, has_cache = false, max_tokens_extended = false)
    extra_headers = ["anthropic-version" => "2023-06-01"]
    beta_features = String[]
    has_tools && push!(beta_features, "tools-2024-04-04")
    has_cache && push!(beta_features, "prompt-caching-2024-07-31")
    max_tokens_extended && push!(beta_features, "max-tokens-3-5-sonnet-2024-07-15")
    !isempty(beta_features) && push!(extra_headers, "anthropic-beta" => join(beta_features, ","))
    return extra_headers
end

function stream_response(prompt::String; system_msg="", model::String="claude-3-5-sonnet-20240620", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false, cache::Union{Nothing,Symbol}=nothing, top_p=nothing) 
    return stream_response([Dict("role" => "user", "content" => prompt)]; system_msg, model, max_tokens, printout, verbose, cache, top_p)
end

function is_sonnet(model)
    model ∈ Set(("claude-3-5-sonnet-20241022", "claude-3-5-sonnet-20240620", "claude-3-5-sonnet-latest"))
end

function stream_response(msgs::Vector{Dict{String,T}}; system_msg="", model::String="claude-3-5-sonnet-20240620", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false, cache::Union{Nothing,Symbol}=nothing, top_p=nothing) where {T}
    processed_msgs = []
    for msg in msgs
        if msg["role"] == "user" && msg["content"] isa Vector
            # Handle image + text input
            processed_content = []
            for item in msg["content"]
                if item isa Dict && item["type"] == "image"
                    push!(processed_content, process_image(item["source"]["path"]))
                else
                    push!(processed_content, item)#Dict("type" => "text", "text" => item))
                end
            end
            push!(processed_msgs, Dict("role" => "user", "content" => processed_content))
        else
            # Handle text-only input
            push!(processed_msgs, msg)
        end
    end
    
    body = Dict("messages" => convert_user_messages(msgs), "model" => model, "max_tokens" => max_tokens, "stream" => true)
    !isnothing(top_p) && (body["top_p"] = top_p)
    @assert is_valid_message_sequence(body["messages"]) "Invalid message sequence. Messages should alternate between 'user' and 'assistant', starting with 'user'. "
    
    !isempty(system_msg) && (body["system"] = system_msg)
    
    headers = [
        "Content-Type" => "application/json",
        "X-API-Key" => get_api_key(),
    ]
    
    # Add anthropic-beta header if needed
    extra_headers = anthropic_extra_headers(
        has_cache = !isnothing(cache),
        max_tokens_extended = (max_tokens > 4096 && is_sonnet(model))
    )
    append!(headers, extra_headers)
    
    # Apply cache control if specified
    if !isnothing(cache)
        # Apply cache control to all messages if cache is :last or :all
        if cache == :last || cache == :all
            for msg in body["messages"][max(end-2, 1):end]
                if msg["role"] == "user" && !isempty(msg["content"])
                    msg["content"][end]["cache_control"] = Dict("type" => "ephemeral")
                end
            end
        end
        
        # Apply cache control to the system message if present
        if (cache == :system || cache == :all) && haskey(body, "system")
            body["system"] = [Dict("type" => "text", "text" => body["system"], "cache_control" => Dict("type" => "ephemeral"))]
        end
    end
    
    channel = Channel{String}(2000)
    @async_showerr (
        HTTP.open("POST", "https://api.anthropic.com/v1/messages", headers; status_exception=false) do io
            write(io, JSON.json(body))
            HTTP.closewrite(io)
            HTTP.startread(io)
            buffer = IOBuffer()
            while !eof(io)
                chunk = String(readavailable(io))
                write(buffer, chunk)
                seekstart(buffer)
                while !eof(buffer)
                    line = readline(buffer, keep=true)
                    if isempty(line)
                        break  # No more complete lines in the buffer
                    end
                    if line == "data: [DONE]\n\n"  # DOESN'T EXIST in anthropic!! ??? It was there in the past by the way!
                        put!(channel, line)
                        printout && print(line)
                        close(channel)
                        return
                    elseif startswith(line, "data: ")
                        jsonline = line[6:end]  # Remove "data: " prefix
                        try
                            # Try to parse as JSON to ensure it's complete
                            data = JSON.parse(jsonline)
                            # Add model information to the data
                            data["model"] = model
                            put!(channel, JSON.json(data))
                            printout && verbose && println(JSON.json(data))
                        catch e
                            # If it's not valid JSON, it's probably incomplete
                            # Put it back in the buffer and wait for more data
                            seekstart(buffer)
                            write(buffer, line)
                            break
                        end
                    else
                        # Non-data line, just pass it through
                        put!(channel, line)
                        printout && verbose && println(line)
                    end
                end
                # Clear the processed content from the buffer
                truncate(buffer, 0)
                seekstart(buffer)
            end
            HTTP.closeread(io)
        end;
        isopen(channel) && close(channel)
    )

    return channel
end

function ai_stream_safe(msgs; model, max_tokens=DEFAULT_MAX_TOKEN, printout=true, system_msg="", cache=nothing, top_p=nothing) 
    return stream_response(msgs; system_msg, model, max_tokens, printout, cache, top_p)
end

function ai_ask_safe(conversation::Vector{Dict{String,String}}; model, return_all=false, max_token=DEFAULT_MAX_TOKEN, cache=nothing)     
    return safe_fn(aigenerate, 
    [
        msg["role"] == "system" ? SystemMessage(msg["content"]) :
        msg["role"] == "user" ? UserMessage(msg["content"]) :
        msg["role"] == "assistant" ? AIMessage(msg["content"]) : UserMessage(msg["content"])
        for msg in conversation
    ]; model, return_all, max_token, cache)
end

function ai_ask_safe(conversation; model, return_all=false, max_token=DEFAULT_MAX_TOKEN, cache=nothing)     
    return safe_fn(aigenerate, conversation; model, return_all, max_token, cache)
end

end # module Anthropic
