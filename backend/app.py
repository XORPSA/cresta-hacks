from flask import Flask, request, jsonify, session
from flask_cors import CORS
from routes.knowledge import knowledge_bp

app = Flask(__name__)
CORS(app)
app.register_blueprint(knowledge_bp, url_prefix="/knowledge")


@app.route('/')
def index():
    return jsonify({"message": "Hello, World!"})

if __name__ == '__main__':
    app.run(debug=True)
