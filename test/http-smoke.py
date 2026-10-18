"""Exercise actual Emacs HTTP transport against a local, fake Choice API."""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

requests = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append((self.path, self.headers.get('Authorization'), body))
        names = list(body['questions']['command']['criteria'])
        probabilities = {name: (0.9 if name == 'dired' else 0.1) for name in names}
        data = json.dumps({'answers': {'command': {
            'type': 'choice', 'choice': 'dired', 'probabilities': probabilities,
        }}}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
expression = r'''(let ((choicel-systemone-url "http://127.0.0.1:PORT/v1/systemone")
                       (choicel-systemone-api-key (lambda () "smoke-key"))
                       (choicel-systemone-model "smoke-model")
                       (choicel-systemone-survivors 1)
                       (deadline (+ (float-time) 10)) done result failure)
  (choicel-systemone-search "ディレクトリ一覧を開きたい" '((major_mode . "fundamental-mode"))
                           '((dired "Edit a directory") (ignore "Ignore"))
                           (lambda (entries error)
                             (setq done t result entries failure error)))
  (while (and (not done) (< (float-time) deadline)) (accept-process-output nil 0.05))
  (unless (and done (not failure) (eq (caar result) 'dired))
    (error "HTTP smoke failed: %S" failure))
  (princ "Real HTTP transport: passed\n"))'''.replace('PORT', str(server.server_port))
expression = ''.join(char if ord(char) < 128 else '\\u%04x' % ord(char) for char in expression)
try:
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else 'emacs',
                    '-Q', '--batch', '-L', '.', '-l', 'choicel', '--eval', expression],
                   check=True, timeout=20)
    assert len(requests) == 1
    path, authorization, payload = requests[0]
    assert path == '/v1/systemone'
    assert authorization == 'Bearer smoke-key'
    assert payload['model'] == 'smoke-model'
    assert payload['state']['query'] == 'ディレクトリ一覧を開きたい'
finally:
    server.shutdown()
    server.server_close()
