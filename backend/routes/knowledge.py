from flask import Blueprint, request, jsonify
from services.knowledge_service import KnowledgeService

knowledge_bp = Blueprint("knowledge", __name__)

@knowledge_bp.route("/curate", methods=["POST"])
def curate():
    """
    Add new knowledge.
    Frontend sends a JSON payload with the new knowledge.
    """
    data = request.json
    response = KnowledgeService.curate(data)
    return jsonify(response)

@knowledge_bp.route("/purge", methods=["POST"])
def purge():
    """
    Delete outdated knowledge.
    Frontend sends a JSON payload with purge rules or IDs.
    """
    data = request.json
    response = KnowledgeService.purge(data)
    return jsonify(response)
