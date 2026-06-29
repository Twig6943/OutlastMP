import asyncio

HOST = "127.0.0.1"
PORT = 7777

clients = set()

async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    addr = writer.get_extra_info("peername")
    print(f"Outlast Client Connected from {addr}")
    clients.add(writer)
    
    try:
        while True:
            data = await reader.read(1024)
            if not data:
                print(f"[{addr}] Disconnected")
                break
            
            # Broadcast to all OTHER clients
            for client in clients:
                if client != writer:
                    try:
                        client.write(data)
                        await client.drain()
                    except Exception as e:
                        pass
    except asyncio.IncompleteReadError:
        pass
    except ConnectionResetError:
        print(f"[{addr}] Connection reset by client")
    finally:
        clients.remove(writer)
        writer.close()
        await writer.wait_closed()

async def main():
    server = await asyncio.start_server(handle_client, HOST, PORT)
    print(f"[server] Listening on {HOST}:{PORT}")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
