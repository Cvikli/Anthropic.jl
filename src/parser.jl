# New parsing functions
parse_text_delta(data) = return get(get(data, "delta", Dict()), "text", "")

function parse_message_start(data, model)
    message = get(data, "message", Dict())
    usage = get(message, "usage", Dict())
    data = Dict{String,Any}(
        "id" => get(message, "id", ""),
        "input_tokens"  => get(usage, "input_tokens",  0),
        "output_tokens" => get(usage, "output_tokens", 0),
        "cache_creation_input_tokens" => get(usage, "cache_creation_input_tokens", 0),
        "cache_read_input_tokens"     => get(usage, "cache_read_input_tokens",     0),
    )
    data["price"] = append_calculated_cost(data, model)
    return data
end

function parse_message_delta(data, model)
    usage = get(data, "usage", Dict())
    delta = get(data, "delta", Dict())
    data = Dict{String,Any}(
        "input_tokens"  => get(usage, "input_tokens",  0),
        "output_tokens" => get(usage, "output_tokens", 0),
        "cache_creation_input_tokens" => get(usage, "cache_creation_input_tokens", 0),
        "cache_read_input_tokens"     => get(usage, "cache_read_input_tokens",     0),
        "stop_reason"   => get(delta, "stop_reason", ""),
        )
    data["stop_sequence"] = delta["stop_reason"] == "stop_sequence" ? delta["stop_sequence"] : "" 
    data["price"] = append_calculated_cost(data, model)
    return data
end

function parse_error(data)
    error = get(data, "error", Dict())
    return Dict(
        "type"    => get(error, "type",    "unknown"),
        "message" => get(error, "message", "Unknown error"),
        "details" => get(error, "details", "")
    )
end

function parse_stream_data(raw_data::String)
    # @show raw_data
    # Handle special cases
    raw_data == "data: [DONE]\n\n" && return [(:done, nothing)]
    raw_data == "\n" && return []
    startswith(raw_data, "event: ") && return [(:meta, nothing)]
 
    data = try
        JSON.parse(raw_data)
    catch e
        return [(:error, Dict("type"=>"json_error", "message"=>"Failed to parse JSON: $raw_data"))]  # we throw this data away
        # return [(:partial, raw_data)]  # If JSON parsing fails, assume partial data
    end

    model = get(data, "model", "unknown")
    events = []
    if haskey(data, "type")
        if data["type"] == "message_start"
            push!(events, (:meta_usr, parse_message_start(data, model)))
        elseif data["type"] == "content_block_start"
            # Handle content block start if needed
        elseif data["type"] == "content_block_delta"
            push!(events, (:text, parse_text_delta(data)))
        elseif data["type"] == "content_block_stop"
            # Handle content block stop if needed
        elseif data["type"] == "message_delta"
            push!(events, (:meta_ai, parse_message_delta(data, model)))
        elseif data["type"] == "message_stop"
            push!(events, (:done, nothing))
        elseif data["type"] == "ping"
            push!(events, (:ping, get(data, "data", nothing)))
        elseif data["type"] == "error"
            push!(events, (:error, data))
        else
            @warn "Unhandled event type: $(data["type"]) $data"
        end
    # elseif haskey(data, "delta") && haskey(data["delta"], "type")
    #     # This is for compatibility with the original format
    #     delta_type = data["delta"]["type"]
    #     if delta_type == "text_delta"
    #         push!(events, (:text, parse_text_delta(data)))
    #     elseif delta_type == "message_delta"
    #         push!(events, (:meta_ai, parse_message_delta(data, model)))
    #     else
    #         @warn "Unhandled delta type: $delta_type"
    #     end
    else
        @warn "Unexpected data format: $data"
        @assert false "These case should be handled above... so if we face a new case then we have to extend the handled case list!"
    end

    return events
end

function process_stream(channel::Channel;
    on_start::Function    = () -> nothing,
    on_text::Function     = (text) -> print(text),
    on_meta_usr::Function = (meta) -> nothing,
    on_meta_ai::Function  = (meta, full_msg) -> nothing,
    on_error::Function    = (error) -> @error("Error in stream: $error"),
    on_done::Function     = () -> @debug("Stream finished"),
    on_ping::Function     = (data) -> @debug("Received ping: $data")
)
    local start_time_usr
    start_time = time()
    on_start()
    
    full_response = ""
    
    buffer = ""
    for chunk in channel
        if !isempty(buffer)
            chunk = buffer * chunk
            buffer = ""
        end

        for (type, content) in parse_stream_data(chunk)
            if type == :partial
                buffer = content  # Store partial data for next iteration. Sadly this can cause unparseable data to be sent back if some really unparseable garbage arrives...
            elseif type == :text
                full_response *= content
                on_text(content)
            elseif type == :meta_usr
                start_time_usr = time()
                content["elapsed"] = start_time_usr - start_time
                on_meta_usr(content)
            elseif type == :meta_ai
                start_time_ai = time()
                content["elapsed"] = start_time_ai - start_time_usr
                on_meta_ai(content, full_response)
            elseif type == :ping
                on_ping(content)
            elseif type == :error
                err = get(content, "error", nothing)
                if isnothing(err)
                    @warn content
                else
                    @warn err
                end
                on_error(content)
            elseif type == :done
                on_done()
            end
        end
    end
    
    return full_response
end

