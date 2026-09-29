#!/usr/bin/env python3
"""Coleta o Profiler do Godot (o mesmo da aba Profiler do editor) sem o editor.

Abre o servidor de depuração remota, espera o jogo conectar (godot --remote-debug tcp://127.0.0.1:PORT),
liga o profiler "servers" (inclui o tempo por função de script) e agrega os quadros recebidos.
Só stdlib. Uso:

  python3 tools/bench/godot_profiler.py --port 6010 --skip 120 --out perfil.json -- \
      godot --headless --path . --fixed-fps 60 --remote-debug tcp://127.0.0.1:6010 \
      -s res://tools/bench/stress_bench.gd -- allies=40 enemies=40 profile=warriors phase=full

O comando depois de `--` é iniciado por este script. Saída: JSON com o total por função
(self/total em ms por quadro, chamadas por quadro) e o resumo de tempos do motor por quadro.
"""
import argparse
import json
import socket
import struct
import subprocess
import sys
import threading
import time

# --- Variant (formato binário do Godot 4) ---------------------------------------------------
NIL, BOOL, INT, FLOAT, STRING = 0, 1, 2, 3, 4
VECTOR2, VECTOR2I, RECT2, RECT2I, VECTOR3, VECTOR3I = 5, 6, 7, 8, 9, 10
COLOR, STRING_NAME, NODE_PATH, RID, OBJECT = 20, 21, 22, 23, 24
DICTIONARY, ARRAY = 27, 28
PACKED_BYTE, PACKED_I32, PACKED_I64, PACKED_F32, PACKED_F64, PACKED_STR = 29, 30, 31, 32, 33, 34
FLAG_64 = 1 << 16


class Reader:
    def __init__(self, b):
        self.b, self.i = b, 0

    def u32(self):
        v = struct.unpack_from("<I", self.b, self.i)[0]
        self.i += 4
        return v

    def take(self, fmt):
        v = struct.unpack_from(fmt, self.b, self.i)
        self.i += struct.calcsize(fmt)
        return v

    def string(self):
        n = self.u32()
        s = self.b[self.i:self.i + n].decode("utf-8", "replace")
        self.i += n + ((4 - n % 4) % 4)
        return s

    def variant(self):
        h = self.u32()
        t = h & 0xFF
        f64 = bool(h & FLAG_64)
        if t == NIL:
            return None
        if t == BOOL:
            return bool(self.u32())
        if t == INT:
            return self.take("<q" if f64 else "<i")[0]
        if t == FLOAT:
            return self.take("<d" if f64 else "<f")[0]
        if t in (STRING, STRING_NAME, NODE_PATH):
            if t == NODE_PATH:
                raise ValueError("NodePath não suportado")
            return self.string()
        if t in (VECTOR2, VECTOR2I):
            return self.take(("<dd" if f64 else "<ff") if t == VECTOR2 else "<ii")
        if t in (RECT2, RECT2I, COLOR):
            return self.take(("<dddd" if f64 else "<ffff") if t != RECT2I else "<iiii")
        if t in (VECTOR3, VECTOR3I):
            return self.take(("<ddd" if f64 else "<fff") if t == VECTOR3 else "<iii")
        if t == RID:
            return self.take("<Q")[0]
        if t == OBJECT:
            return self.take("<Q")[0] if f64 else None
        if t in (ARRAY, DICTIONARY):
            kind = (h >> 16) & 0x3   # tipo do contêiner (arrays tipados)
            if t == ARRAY and (h >> 16) & 0x3 and not f64:
                pass
            n = self.u32() & 0x7FFFFFFF
            if t == ARRAY:
                return [self.variant() for _ in range(n)]
            return {self.variant(): self.variant() for _ in range(n)}
        if t == PACKED_BYTE:
            n = self.u32()
            v = self.b[self.i:self.i + n]
            self.i += n + ((4 - n % 4) % 4)
            return v
        if t in (PACKED_I32, PACKED_F32):
            n = self.u32()
            return list(self.take("<%d%s" % (n, "i" if t == PACKED_I32 else "f")))
        if t in (PACKED_I64, PACKED_F64):
            n = self.u32()
            return list(self.take("<%d%s" % (n, "q" if t == PACKED_I64 else "d")))
        if t == PACKED_STR:
            return [self.string() for _ in range(self.u32())]
        raise ValueError("Variant tipo %d não suportado" % t)


def enc(v):
    if v is None:
        return struct.pack("<I", NIL)
    if isinstance(v, bool):
        return struct.pack("<II", BOOL, int(v))
    if isinstance(v, int):
        return struct.pack("<Iq", INT | FLAG_64, v)
    if isinstance(v, float):
        return struct.pack("<Id", FLOAT | FLAG_64, v)
    if isinstance(v, str):
        b = v.encode()
        return struct.pack("<II", STRING, len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)
    if isinstance(v, list):
        return struct.pack("<II", ARRAY, len(v)) + b"".join(enc(x) for x in v)
    raise TypeError(type(v))


def send(conn, msg, data):
    payload = enc([msg, 1, data])
    conn.sendall(struct.pack("<I", len(payload)) + payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=6010)
    ap.add_argument("--skip", type=int, default=120, help="quadros iniciais descartados")
    ap.add_argument("--out", required=True)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd

    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", a.port))
    srv.listen(1)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    srv.settimeout(60)
    conn, _ = srv.accept()
    conn.settimeout(None)
    send(conn, "profiler:servers", [True, [256]])

    sigs, frames, msgs, errors = {}, [], {}, []
    buf = b""
    stop = threading.Event()

    def pump_stdout():
        for line in proc.stdout:
            if line.startswith("BENCH"):
                print(line.rstrip())
    threading.Thread(target=pump_stdout, daemon=True).start()

    while True:
        try:
            chunk = conn.recv(1 << 20)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        while len(buf) >= 4:
            n = struct.unpack_from("<I", buf)[0]
            if len(buf) < 4 + n:
                break
            pkt, buf = buf[4:4 + n], buf[4 + n:]
            try:
                m = Reader(pkt).variant()
            except Exception as e:   # mensagem com tipo não suportado: ignora
                msgs["<erro de decodificação>"] = msgs.get("<erro de decodificação>", 0) + 1
                continue
            name, data = m[0], m[2] if len(m) > 2 else m[1]
            msgs[name] = msgs.get(name, 0) + 1
            if name == "servers:function_signature":
                sigs[data[1]] = data[0]
            elif name == "servers:profile_frame":
                frames.append(data)
            elif name == "error" and len(errors) < 50:
                errors.append([x for x in data if isinstance(x, (str, int, bool))])
    proc.wait()

    # ServersProfilerFrame.serialize(): [frame, frame_time, process_time, physics_time, physics_frame_time,
    #   script_time, n_servers, (nome, 2k, (func, tempo)×k)×n_servers, 4f|5f, (sig, calls, self, total[, internal])×f]
    agg, eng, used = {}, {"frame_time": 0.0, "process_time": 0.0, "physics_time": 0.0, "script_time": 0.0}, 0
    servers = {}
    for fr in frames[a.skip:]:
        i = 0
        _, ft, pt, ph, _pft, st = fr[0:6]
        i = 6
        eng["frame_time"] += ft
        eng["process_time"] += pt
        eng["physics_time"] += ph
        eng["script_time"] += st
        ns = fr[i]
        i += 1
        for _ in range(ns):
            sname = fr[i]
            cnt = fr[i + 1]
            i += 2
            for j in range(0, cnt, 2):
                key = "%s::%s" % (sname, fr[i + j])
                servers[key] = servers.get(key, 0.0) + fr[i + j + 1]
            i += cnt
        cnt = fr[i]
        i += 1
        rest = fr[i:i + cnt]
        stride = 5 if cnt % 5 == 0 and (cnt % 4 != 0 or len(rest) and not isinstance(rest[4 % len(rest)], int)) else 4
        for j in range(0, cnt, stride):
            sig, calls, self_t, total_t = rest[j:j + 4]
            e = agg.setdefault(sig, [0, 0.0, 0.0])
            e[0] += calls
            e[1] += self_t
            e[2] += total_t
        used += 1
    n = max(used, 1)
    funcs = sorted(({"function": sigs.get(s, str(s)), "calls_per_frame": v[0] / n, "self_ms_per_frame": v[1] * 1000.0 / n,
                     "total_ms_per_frame": v[2] * 1000.0 / n} for s, v in agg.items()), key=lambda x: -x["self_ms_per_frame"])
    out = {
        "frames": used, "messages": msgs, "errors": errors,
        "engine_ms_per_frame": {k: v * 1000.0 / n for k, v in eng.items()},
        "servers_ms_per_frame": {k: v * 1000.0 / n for k, v in sorted(servers.items(), key=lambda x: -x[1])},
        "functions": funcs,
    }
    json.dump(out, open(a.out, "w"), indent=1)
    print("quadros:", used, "funções:", len(funcs), "->", a.out)
    for f in funcs[:25]:
        print("%8.3f ms self %8.3f ms total %8.1f calls  %s" % (f["self_ms_per_frame"], f["total_ms_per_frame"], f["calls_per_frame"], f["function"]))


if __name__ == "__main__":
    main()
