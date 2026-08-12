import json, socket, sys, pathlib
HOST, PORT = "localhost", 9876
def call(code, timeout=180.0):
    try:
        conn = socket.create_connection((HOST, PORT), timeout=timeout)
    except OSError as ex:
        return {"status":"error","message":"cannot reach Blender %s"%ex}
    try:
        conn.sendall((json.dumps({"type":"execute","code":code,"strict_json":False})+"\0").encode())
        conn.settimeout(timeout)
        buf = bytearray()
        while b"\0" not in buf:
            c = conn.recv(65536)
            if not c: break
            buf.extend(c)
    finally:
        conn.close()
    if b"\0" not in buf: return {"status":"error","message":"incomplete"}
    return json.loads(bytes(buf[:buf.index(b"\0")]))
if __name__ == "__main__":
    src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8") if len(sys.argv)>1 else sys.stdin.read()
    r = call(src)
    print(json.dumps(r, indent=1)[:12000])
