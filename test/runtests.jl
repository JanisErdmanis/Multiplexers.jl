using Multiplexers
using Sockets
using Serialization

N = 1
@sync begin
    @async let
        server = listen(2014)
        try
            socket = accept(server)
            mux = Multiplexer(socket,N)

            # Tesing Serializer
            serialize(mux.lines[1],"from serializer")
            @show deserialize(mux.lines[1])

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

        # Testing serializer
        @show deserialize(mux.lines[1])
        serialize(mux.lines[1],"HEllo")

        # Testing asynchronous conection
        @async serialize(mux.lines[1],"Hello from there")
        @show deserialize(mux.lines[1])

        wait(mux)
    end
end


