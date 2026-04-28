from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/")
def index():
    return "<h1>Hello from Azure App Service!</h1><p>GitHub Actions OIDC 배포 성공</p>"

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    app.run(host="0.0.0.0", port=port)
