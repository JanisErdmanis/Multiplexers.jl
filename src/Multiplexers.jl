module Multiplexers

# I could extend Base.write and Base.read?
# Would be great to work on byte level.

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

### Some high end interface
struct Multiplexer{T<:IO} 
    socket::IO
    lines::Vector{T}
    daemon::Task
end

function Multiplexer(socket::IO,N::Integer)
    lines = Line[Line(socket,i) for i in 1:N]
    daemon = @async route(lines,socket)
    Multiplexer(socket,lines,daemon)
end

import Base.wait
wait(mux::Multiplexer) = wait(mux.daemon)

import Base.close
function close(mux::Multiplexer)
    serialize(mux.socket,:Terminate)
    wait(mux)
end


"""
A function which one uses to forward forward traffic from multiple sockets into one socket by multiplexing.
"""
function forward(ios::Vector{IO},socket::IO)
    mux = Multiplexer(socket,length(ios))
    
    tasks = []

    for (line,io) in zip(mux.lines,ios)
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

    wait(mux)
    deserialize(socket)==:Terminate

    for t in tasks
        @async Base.throwto(t,InterruptException()) 
    end
end

function Multiplexer(socket::IO,ios::Vector{IO})
    daemon = @async forward(ios,socket)
    Multiplexer(socket,ios,daemon)
end

export Multiplexer, Line, serialize, deserialize

end # module
