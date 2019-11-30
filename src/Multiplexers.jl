module Multiplexers

struct Line <: IO
    socket::IO
    ch::Channel
    n::Integer
    
    function Line(socket,ch,n)
        @assert hasmethod(serialize,(typeof(socket),Any))
        @assert hasmethod(deserialize,(typeof(socket),))
        new(socket,ch,n)
    end
end

Line(socket,n) = Line(socket,Channel(),n)

serialize(line::Line,msg) = serialize(line.socket,(line.n,msg))
deserialize(line::Line) = take!(line.ch)

"""
Takes multiple input lines and routes them to a single line.
"""
function route(lines::Vector{Line},socket::IO)
    while true
        data = deserialize(socket)
        if data==:Terminate
            serialize(socket,:Terminate)
            return
        else
            n,msg = data
            put!(lines[n].ch,msg)
        end
    end
end

"""
A function which one uses to forward forward traffic from multiple sockets into one socket by multiplexing.
"""
function route(ios::Vector{IO},socket::IO)
    lines = [Line(socket,i) for i in 1:length(ios)]
    task = @async route(lines,socket)
    
    tasks = []

    for (line,io) in zip(lines,ios)
        task1 = @async while true
            msg = deserialize(line)
            serialize(io,msg)
        end 
        push!(tasks,task1)
        
        task2 = @async while true
            msg = deserialize(io)
            serialize(line,msg)
        end
        push!(tasks,task2)
    end

    wait(task)
    for t in tasks
        @async Base.throwto(t,InterruptException()) 
    end
end

export Line, route, serialize, deserialize

end # module
