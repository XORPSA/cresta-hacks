from flask import Flask, request, jsonify, session
from flask_cors import CORS
from settings import Settings

app = Flask(__name__)
CORS(app)

@app.route('/')
def index():
    return jsonify({"message": "Hello, World!"})

if __name__ == '__main__':
    app.run(debug=True)