#using Multiplexers
using Sockets

import Multiplexers
import Multiplexers: Line, route

# serialize(io::Line,msg) = Multiplexers.serialize(io,msg)
# deserialize(io::Line) = Multiplexers.deserialize(io)
import Multiplexers: serialize, deserialize

import Serialization
serialize(io::Union{TCPSocket,IOBuffer},msg) = Serialization.serialize(io,msg)
deserialize(io::Union{TCPSocket,IOBuffer}) = Serialization.deserialize(io)

N = 1
@sync begin
    @async let
        server = listen(2014)
        try
            socket = accept(server)
            lines = [Line(socket,i) for i in 1:N]

            task = @async route(lines,socket)

            serialize(lines[1],"Hello World")

            serialize(socket,:Terminate)
            wait(task)
        finally
            close(server)
        end
    end

    @async let
        socket = connect(2014)
        lines = [Line(socket,i) for i in 1:N]

        task = @async route(lines,socket)
        @show deserialize(lines[1])
        #serialize(socket,:Terminate)
        wait(task)
    end
end


