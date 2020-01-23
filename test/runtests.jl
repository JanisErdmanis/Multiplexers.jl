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

            #serialize(mux.lines[1],"Hello World")
            write(mux.lines[1],"Hello World")

            # Testing asynchronous conection
            @async write(mux.lines[1],"Hello from here")
            @show String(readavailable(mux.lines[1]))

            # Tesing Serializer
            serialize(mux.lines[1],"from serializer")

            close(mux)
        finally
            close(server)
        end
    end

    @async let
        socket = connect(2014)
        mux = Multiplexer(socket,N)
        
        @show String(readavailable(mux.lines[1]))

        @async write(mux.lines[1],"Hello from there")
        @show String(readavailable(mux.lines[1]))

        # Testing serializer
        @show deserialize(mux.lines[1])

        wait(mux)
    end
end


