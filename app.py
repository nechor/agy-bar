import requests
from flask import Flask, jsonify, render_template

app = Flask(__name__)

# Game widget endpoint
WIDGET_API_URL = "http://127.0.0.1:8540/"

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/data")
def get_data():
    try:
        response = requests.get(WIDGET_API_URL, timeout=1.0)
        if response.status_code == 200:
            return jsonify(response.json())
        else:
            return jsonify({
                "status": "error",
                "message": f"Game widget returned status {response.status_code}"
            }), 502
    except requests.exceptions.RequestException as e:
        return jsonify({
            "status": "error",
            "message": "Nie można połączyć się z grą. Upewnij się, że Beyond All Reason jest uruchomiony, mecz trwa, a widget 'HTTP API Server v2' jest włączony (F11)."
        }), 503

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
