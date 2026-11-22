import socket,subprocess,threading,json,time,pathlib,tempfile
with tempfile.TemporaryDirectory() as td:
 s=socket.socket(socket.AF_UNIX);s.bind(td+'/s');s.listen();s.settimeout(.1);rows=[];stop=False
 def serve():
  while not stop:
   try:c,_=s.accept()
   except socket.timeout:continue
   with c:
    buf=b''
    while True:
     b=c.recv(4096)
     if not b:break
     buf+=b
    rows.append(json.loads(buf)['command']);time.sleep(.025)
    try:c.sendall(b'{"error":"success"}\n')
    except BrokenPipeError:pass
 t=threading.Thread(target=serve);t.start()
 try:subprocess.run(['/tmp/gor184-ipc-stress/check',td+'/s'],check=True,timeout=5)
 finally:stop=True;t.join();s.close()
 assert ['pose',499] in rows,rows
 key=rows.index(['key','pause']);quit=rows.index(['quit'])
 assert key<=2 and quit==len(rows)-1 and len(rows)<10,rows
 print('PASS actual production IPCClient (Darwin/Glibc shim only), 500poses,25ms owned Unix socket, latest499/key<=2/quit-final/no500..999:',rows)
 pathlib.Path('/tmp/gor184-ipc-stress/result.txt').write_text(repr(rows)+'\n')
