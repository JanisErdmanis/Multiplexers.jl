using Multiplexers
using Sockets

import Serialization

import Multiplexers: serialize, deserialize
serialize(io::Union{TCPSocket,IOBuffer},msg) = Serialization.serialize(io,msg)
deserialize(io::Union{TCPSocket,IOBuffer}) = Serialization.deserialize(io)

N = 1
@sync begin
    @async let
        server = listen(2014)
        try
            socket = accept(server)
            mux = Multiplexer(socket,N)

            task = @async route(mux)

            serialize(mux.lines[1],"Hello World")

            serialize(socket,:Terminate)
            wait(task)
        finally
            close(server)
        end
    end

    @async let
        socket = connect(2014)
        mux = Multiplexer(socket,N)

        task = @async route(mux)
        @show deserialize(mux.lines[1])
        wait(task)
    end
end


