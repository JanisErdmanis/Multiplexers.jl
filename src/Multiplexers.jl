module Multiplexers

using Serialization

import Base.sync_varname
import Base.@async

macro async(expr)

    tryexpr = quote
        try
            $expr
        catch err
            @warn "error within async" exception=err # line $(__source__.line):
        end
    end

    thunk = esc(:(()->($tryexpr)))

    var = esc(sync_varname)
    quote
        local task = Task($thunk)
        if $(Expr(:isdefined, var))
            push!($var, task)
        end
        schedule(task)
        task
    end
end


# I could extend Base.write and Base.read?
# Would be great to work on byte level.

mutable struct Line <: IO
    socket::IO
    ch::Channel{UInt8}
    n::Integer
end

Line(socket,n) = Line(socket,Channel{UInt8}(Inf),n)

import Base.write
write(line::Line,msg::UInt8) = serialize(line.socket,(line.n,msg))
write(line::Line,msg::String) = serialize(line.socket,(line.n,msg))
write(line::Line,msg::Vector{UInt8}) = serialize(line.socket,(line.n,msg))

import Base.read
read(line::Line,x::Type{UInt8}) = take!(line.ch)

import Base.readavailable
function readavailable(line::Line) 
    wait(line.ch)
    s = UInt8[]
    while isready(line.ch)
        push!(s,take!(line.ch))
    end
    return s #[end:-1:1]
end

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
            
            if typeof(msg)==UInt8
                put!(lines[n].ch,msg)
            else
                bmsg = take!(IOBuffer(msg))
                for byte in bmsg #[end:-1:1]
                    put!(lines[n].ch,byte)
                end
            end
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

export Multiplexer, Line, read, readavailable, write #serialize, deserialize

end # module
