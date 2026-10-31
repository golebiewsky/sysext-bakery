import pathlib, socket, struct, subprocess, signal, time
root = pathlib.Path(__file__).resolve().parent / 'artifacts'
binary = root / 'root-x86/usr/bin/coredns'
config = root / 'Corefile.runtime'
def write(ip):
    config.write_text(f'''.:10539 {{
    bind 127.0.0.1
    errors
    hosts {{
        {ip} sysext.test
        ttl 1
    }}
}}\n''')
def query(tcp=False):
    name = b''.join(bytes([len(x)]) + x.encode() for x in 'sysext.test'.split('.')) + b'\0'
    packet = struct.pack('!6H', 1234, 256, 1, 0, 0, 0) + name + struct.pack('!2H', 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM if tcp else socket.SOCK_DGRAM) as s:
        s.settimeout(.2)
        if tcp:
            s.connect(('127.0.0.1', 10539))
            s.sendall(struct.pack('!H', len(packet)) + packet)
            n = struct.unpack('!H', s.recv(2))[0]
            reply = b''
            while len(reply) < n:
                chunk = s.recv(n - len(reply))
                if not chunk:
                    raise OSError('DNS connection closed before the complete reply')
                reply += chunk
        else:
            s.sendto(packet, ('127.0.0.1', 10539))
            reply, _ = s.recvfrom(4096)
    assert struct.unpack('!6H', reply[:12])[3] == 1, reply.hex()
    return socket.inet_ntoa(reply[-4:])
def wait_for(ip):
    for _ in range(80):
        try:
            if query() == ip and query(True) == ip:
                return
        except (OSError, AssertionError):
            pass
        time.sleep(.1)
    raise AssertionError(f'DNS did not return {ip}')
write('192.0.2.10')
with (root / 'runtime.log').open('w') as log:
    p = subprocess.Popen([str(binary), '-conf', str(config)], stdout=log, stderr=subprocess.STDOUT)
    try:
        wait_for('192.0.2.10')
        print('PASS: UDP and TCP DNS resolve deterministic local record')
        write('192.0.2.20')
        p.send_signal(signal.SIGUSR1)
        wait_for('192.0.2.20')
        print('PASS: SIGUSR1 reload changes UDP and TCP answers without process exit')
        config.write_text('.:10539 {\n invalid_plugin\n}\n')
        p.send_signal(signal.SIGUSR1)
        time.sleep(.5)
        wait_for('192.0.2.20')
        print('PASS: invalid config reload preserves working DNS')
    finally:
        p.terminate()
        p.wait(timeout=10)
    assert p.returncode == 0, p.returncode
    print('PASS: SIGTERM exits cleanly')
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stub:
    stub.bind(('127.0.0.53', 10539))
    config.write_text('.:10539 {\n errors\n hosts {\n 192.0.2.10 sysext.test\n }\n}\n')
    p = subprocess.run([str(binary), '-conf', str(config)], capture_output=True, text=True, timeout=10)
    assert p.returncode != 0 and 'address already in use' in p.stdout + p.stderr, p
    print('PASS: reproduced wildcard listener conflict with a resolver stub on 127.0.0.53')
    (root / 'stub-conflict.log').write_text(p.stdout + p.stderr)
