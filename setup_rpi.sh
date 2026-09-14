#!/bin/bash

# Interromper o script em caso de erro
set -e

echo "=== 1. Atualizando os repositórios e o sistema ==="
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y

echo "=== 2. Instalando MPV, yt-dlp, Python e dependências de áudio/vídeo ==="
apt install -y mpv yt-dlp python3 python3-pip ufw alsa-utils ffmpeg

echo "=== 3. Configurando o Firewall (UFW) ==="
ufw allow 22/tcp          # Acesso SSH
ufw allow 8080/tcp        # Porta da página web de gerenciamento da fila
ufw --force enable

echo "=== 4. Criando o diretório e o servidor da Fila Web ==="
mkdir -p /home/dietpi/streamer

cat << 'EOF' > /home/dietpi/streamer/queue_server.py
import queue
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse

# Fila thread-safe para múltiplos usuários gerenciarem e enviarem links
video_queue = queue.Queue()
current_video = {"url": None, "status": "Aguardando"}

def player_worker():
    """Worker em segundo plano que consome a fila e reproduz os vídeos sequencialmente."""
    global current_video
    while True:
        url = video_queue.get()
        if url:
            current_video["url"] = url
            current_video["status"] = "Reproduzindo"
            print(f"[Player] Iniciando reprodução: {url}")
            
            # Executa o mpv com aceleração de hardware e tela cheia
            process = subprocess.Popen(["mpv", "--hwdec=auto", "--fs", url])
            process.wait()
            
            current_video["url"] = None
            current_video["status"] = "Aguardando"
        video_queue.task_done()

# Inicializa a thread de reprodução em background
threading.Thread(target=player_worker, daemon=True).start()

class StreamHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Página web leve adaptada para múltiplos dispositivos na rede
        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.end_headers()
        
        # Converte a fila atual em lista para exibir os próximos vídeos
        queue_list = list(video_queue.queue)
        
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Fila de Transmissão RPi</title>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; padding: 20px; background: #0f0f0f; color: #fff; }}
                .container {{ max-width: 500px; margin: 0 auto; background: #212121; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.5); }}
                input[type="text"] {{ width: 100%; box-sizing: border-box; padding: 14px; font-size: 16px; border-radius: 6px; border: 1px solid #444; background: #121212; color: #fff; margin-bottom: 15px; }}
                input[type="submit"] {{ background: #cc0000; color: white; border: none; padding: 14px 20px; font-size: 16px; border-radius: 6px; cursor: pointer; width: 100%; font-weight: bold; }}
                input[type="submit"]:hover {{ background: #e60000; }}
                .status-box {{ background: #121212; padding: 15px; border-radius: 6px; margin-top: 20px; text-align: left; font-size: 14px; border-left: 4px solid #cc0000; }}
                ul {{ padding-left: 20px; margin: 5px 0; word-break: break-all; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h2>Fila do YouTube (RPi)</h2>
                <form method="POST">
                    <input type="text" name="url" placeholder="Cole o link do YouTube aqui..." required autofocus>
                    <input type="submit" value="Adicionar à Fila">
                </form>
                <div class="status-box">
                    <p><strong>Estado:</strong> {current_video['status']}</p>
                    <p><strong>Tocando agora:</strong> {current_video['url'] or 'Nenhum'}</p>
                    <p><strong>Próximos na fila ({len(queue_list)}):</strong></p>
                    <ul>
        """
        for item in queue_list:
            html += f"<li>{item}</li>"
            
        html += f"""
                    </ul>
                </div>
            </div>
        </body>
        </html>
        """
        self.wfile.write(html.encode("utf-8"))

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        params = urllib.parse.parse_qs(post_data)
        video_url = params.get("url", [None])[0]

        if video_url:
            print(f"[Servidor] Link enfileirado: {video_url}")
            video_queue.put(video_url)

        self.send_response(303)
        self.send_header('Location', '/')
        self.end_headers()

def run(port=8080):
    server_address = ('', port)
    httpd = HTTPServer(server_address, StreamHandler)
    print(f"Servidor HTTP da fila rodando na porta {port}...")
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

chmod +x /home/dietpi/streamer/queue_server.py

echo "=== 5. Configurando inicialização automática no DietPi ==="
# Adiciona o comando de execução no arquivo de autostart customizado do DietPi
if [ -f /var/lib/dietpi/services/dietpi-autostart.custom ]; then
    grep -q "queue_server.py" /var/lib/dietpi/services/dietpi-autostart.custom || echo "python3 /home/dietpi/streamer/queue_server.py &" >> /var/lib/dietpi/services/dietpi-autostart.custom
fi

echo "=== Deploy e configuração concluídos com sucesso! ==="