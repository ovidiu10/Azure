import socket
import sys
import zlib
import os
import threading
import time
import struct
from socket import error as socket_errordef recv_and_check_data(sock):
    bytes_so_far = 0
    data = b''
    while bytes_so_far < 1028:
        recvd = sock.recv(1028 - bytes_so_far)
        if len(recvd) == 0:
            data = ''
            break
        data += recvd
        bytes_so_far = len(data)
    if len(data) == 0:
        return ""
    computed_crc32 = struct.pack('<L', zlib.crc32(data[:1024]))
    if computed_crc32 != data[1024:1028]:
        print("Corrupted data detected!")
        print(len(data))
        print(repr(data))
        sys.exit(1)
    return datadef server_thread(ready_event):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', int(sys.argv[2])))
    server.listen(1)
    ready_event.set()
    print("Server running.")
    while True:
        (conn, _) = server.accept()
        while True:
            data = recv_and_check_data(conn)
            print("Server: Recv chunk:" + repr(data))
            if len(data) == 0:
                break
            conn.send(data)
            print("Server: Sent chunk")ready_event = threading.Event()
server_thread = threading.Thread(target=server_thread, args=(ready_event,))
server_thread.start()ready_event.wait()not_connected = True
while not_connected:
    try:
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.connect((sys.argv[1], int(sys.argv[2])))
    except socket_error:
        time.sleep(1)
        continue
    not_connected = Falsewhile True:
    data = os.urandom(1024)
    crc = zlib.crc32(data)
    client.send(data + struct.pack('<L', crc))
    print("Client: Sent chunk: " + repr(data + struct.pack('<L', crc)))
    recvd = recv_and_check_data(client)
    print("Client: Recvd chunk: " +repr(recvd))
