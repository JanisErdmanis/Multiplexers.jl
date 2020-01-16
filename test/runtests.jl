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

            serialize(mux.lines[1],"Hello World")

            # Testing asynchronous conection
            @async serialize(mux.lines[1],"Hello from here")
            @show deserialize(mux.lines[1])

            close(mux)
        finally
            close(server)
        end
    end

    @async let
        socket = connect(2014)
        mux = Multiplexer(socket,N)

        @show deserialize(mux.lines[1])

        @async serialize(mux.lines[1],"Hello from there")
        @show deserialize(mux.lines[1])

        wait(mux)
    end
end


