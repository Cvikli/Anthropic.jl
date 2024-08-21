module Anthropic

using HTTP
using JSON
using BoilerplateCvikli: @async_showerr
using PromptingTools: SystemMessage, UserMessage, AIMessage

const API_URL = "https://api.anthropic.com/v1/messages"
const DEFAULT_MAX_TOKEN = 4096

include("error_handler.jl")
include("pricing.jl")


export ai_stream_safe, ai_ask_safe, stream_response

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


stream_response(prompt::String; system_msg="", model::String="claude-3-5-sonnet-20240620", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false) = stream_response([Dict("role" => "user", "content" => prompt)]; system_msg, model, max_tokens, printout, verbose)
function stream_response(msgs::Vector{Dict{String,String}}; system_msg="", model::String="claude-3-opus-20240229", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false)
    body = Dict("messages" => msgs, "model" => model, "max_tokens" => max_tokens, "stream" => true)
    
    system_msg !== "" && (body["system"] = system_msg)
    
    @assert is_valid_message_sequence(body["messages"]) "Invalid message sequence. Messages should alternate between 'user' and 'assistant', starting with 'user'. $(msgs[2:end])"
    
    headers = [
        "Content-Type" => "application/json",
        "X-API-Key" => get_api_key(),
        "anthropic-version" => "2023-06-01"
    ]
    max_tokens>4096 && model=="claude-3-5-sonnet-20240620" && push!(headers, "anthropic-beta"=>"max-tokens-3-5-sonnet-2024-07-15")
    
    
    channel = Channel{String}(2000)
    user_meta, ai_meta = StreamMeta("", 0, 0, 0f0, 0e0), StreamMeta("", 0, 0, 0f0, 0e0)
    start_time = time()
    @async_showerr (
        HTTP.open("POST", "https://api.anthropic.com/v1/messages", headers; status_exception=false) do io
            write(io, JSON.json(body))
            HTTP.closewrite(io)    # indicate we're done writing to the request
            HTTP.startread(io) 
            isdone = false
            while !eof(io) && !isdone
                chunk = String(readavailable(io))

                lines = String.(filter(!isempty, split(chunk, "\n")))
                for line in lines
                    # @show line
                    if startswith(line, "data: ") 
                        line == "data: [DONE]" && (isdone=true; break)
                        data = JSON.parse(replace(line, r"^data: " => ""))
                        if get(get(data, "delta", Dict()), "type", "") == "text_delta"
                            text = data["delta"]["text"]
                            put!(channel, text)
                            printout && (print(text);flush(stdout)   )                
                        elseif data["type"] == "message_start"
                            user_meta.elapsed       = time() # we substract start_time after message arrived!
                            user_meta.id            = get(data["message"],"id","")
                            user_meta.input_tokens  = get(get(data["message"],"usage",Dict()),"input_tokens",0)
                            user_meta.output_tokens = get(get(data["message"],"usage",Dict()),"output_tokens",0)
                            call_cost!(user_meta, model);
                        elseif data["type"] == "message_delta"
                            ai_meta.elapsed       = time() # we substract start_time after message arrived!
                            ai_meta.input_tokens  = get(get(data,"usage",Dict()),"input_tokens",0)
                            ai_meta.output_tokens = get(get(data,"usage",Dict()),"output_tokens",0)
                            call_cost!(ai_meta, model);
                        elseif data["type"] == "message_stop"
                            close(channel)
                        elseif data["type"] in ["content_block_start", "content_block_stop", "ping"]
                            nothing
                        elseif data["type"] == "error"
                            error_type    = get(data["error"], "type", "unknown")
                            error_msg     = get(data["error"], "message", "Unknown error")
                            error_details = get(data["error"], "details", "")
                            
                            if error_type == "overloaded_error"
                                put!(channel, "ERROR: Server overloaded. Please try again later.")
                            elseif error_type == "api_error"
                                put!(channel, "ERROR: Internal server error. Please try again later.")
                            else
                                put!(channel, "ERROR: $error_msg")
                            end
                            
                            println("\nERROR: $error_msg\n")
                            if !isempty(error_details)
                                put!(channel, "Details: $error_details")
                                println("\nDetails: $error_details\n")
                            end
                            isdone = true
                            break
                        else
                            println("unknown packet")
                            println(line)
                         end
                    elseif startswith(line, "event: ") 
                        verbose && println(line)
                    else
                        @show line
                        data = JSON.parse(line)
                        if data["type"] == "error"
                            error_type = get(data["error"], "type", "unknown")
                            error_msg = get(data["error"], "message", "Unknown error")
                            error_details = get(data["error"], "details", "")
                            
                            if error_type == "overloaded_error"
                                put!(channel, "ERROR: Server overloaded. Please try again later.")
                            elseif error_type == "api_error"
                                put!(channel, "ERROR: Internal server error. Please try again later.")
                            else
                                put!(channel, "ERROR: $error_msg")
                            end
                            
                            println("\nERROR: $error_msg\n")
                            if !isempty(error_details)
                                put!(channel, "Details: $error_details")
                                println("\nDetails: $error_details\n")
                            end
                            isdone = true
                            break
                        end
                    end
                    
                end
            end
            HTTP.closeread(io)
        end;
        isopen(channel) && close(channel);
    )

    return channel, user_meta, ai_meta, start_time
end

function channel_to_string(channel::Channel; cb=(()-> return nothing))
    first_text = take!(channel)
    response = first_text
    cb()
    println()
    print("\e[32m¬ \e[0m")
    print(first_text)
    for chunk in channel
        response *= chunk
        print(chunk)
    end
    return response
end

ai_stream_safe(msgs; model, max_tokens=DEFAULT_MAX_TOKEN, printout=true, system_msg="") = safe_fn(stream_response, msgs, system_msg=system_msg, model=model, max_tokens=max_tokens, printout=printout)
ai_ask_safe(conversation::Vector{Dict{String,String}}; model, return_all=false, max_token=DEFAULT_MAX_TOKEN)     = safe_fn(aigenerate, 
 [
    msg["role"] == "system" ? SystemMessage(msg["content"]) :
    msg["role"] == "user" ? UserMessage(msg["content"]) :
    msg["role"] == "assistant" ? AIMessage(msg["content"]) : UserMessage(msg["content"])
    for msg in conversation
], model=model, return_all=return_all, max_token=max_token)
ai_ask_safe(conversation; model, return_all=false, max_token=DEFAULT_MAX_TOKEN)     = safe_fn(aigenerate, conversation, model=model, return_all=return_all, max_token=max_token)

end # module Anthropic
