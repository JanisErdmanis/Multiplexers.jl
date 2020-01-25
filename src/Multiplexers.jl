module Multiplexers

function stack(io::IO,msg::Vector{UInt8})
    frontbytes = reinterpret(UInt8,Int16[length(msg)])
    item = UInt8[frontbytes...,msg...]
    write(io,item)
end

function unstack(io::IO)
    sizebytes = [read(io,UInt8),read(io,UInt8)]
    size = reinterpret(Int16,sizebytes)[1]
    
    msg = UInt8[]
    for i in 1:size
        push!(msg,read(io,UInt8))
    end
    return msg
end

function unstack(io::IOBuffer)
    bytes = take!(io)
    size = reinterpret(Int16,bytes[1:2])[1]
    msg = bytes[3:size+2]
    if length(bytes)>size+2
        write(io,bytes[size+3:end])
    end
    return msg
end

# import Base.sync_varname
# import Base.@async

# macro async(expr)

#     tryexpr = quote
#         try
#             $expr
#         catch err
#             @warn "error within async" exception=err # line $(__source__.line):
#         end
#     end

#     thunk = esc(:(()->($tryexpr)))

#     var = esc(sync_varname)
#     quote
#         local task = Task($thunk)
#         if $(Expr(:isdefined, var))
#             push!($var, task)
#         end
#         schedule(task)
#         task
#     end
# end

struct Line <: IO
    socket::IO
    ch::Channel{UInt8}
    n::UInt8
end

Line(socket,n) = Line(socket,Channel{UInt8}(Inf),UInt8(n))

import Base.write
write(line::Line,msg::UInt8) = stack(line.socket,UInt8[line.n,msg]) 
write(line::Line,msg::Vector{UInt8}) = stack(line.socket,UInt8[line.n,msg...])
write(line::Line,msg::String) = stack(line.socket,UInt8[line.n,msg...])

import Base.read
read(line::Line,x::Type{UInt8}) = take!(line.ch)

"""
Takes multiple input lines and routes them to a single line.
"""
function route(lines::Vector{Line},socket::IO)
    while true
        data = unstack(socket)
        if data==UInt8[0]
            stack(socket,UInt8[0])
            return
        else
            n,msg = Int(data[1]),data[2:end]
            
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
    stack(mux.socket,UInt8[0])
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
            byte = read(line,UInt8)
            write(io,byte)
        end 
        push!(tasks,task1)
        
        task2 = @async while true
            byte = read(io,UInt8)
            write(line,byte) # One needs to think about some kind of buffering (traffic now is multiplied by 2)
        end
        push!(tasks,task2)
    end

    wait(mux)
    @assert unstack(socket)==UInt8[0]

    for t in tasks
        @async Base.throwto(t,InterruptException()) 
    end
end

function Multiplexer(socket::IO,ios::Vector{IO})
    daemon = @async forward(ios,socket)
    Multiplexer(socket,ios,daemon)
end

export Multiplexer, Line, read, write 

end # module
