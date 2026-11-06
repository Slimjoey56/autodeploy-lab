"""Flask application factory for AutoDeploy Lab."""

from flask import Flask, jsonify


def create_app(test_config: dict | None = None) -> Flask:
    """Create and configure the Flask application."""
    app = Flask(__name__)
    app.config.from_mapping(TESTING=False)

    if test_config:
        app.config.update(test_config)

    @app.get("/")
    def index():
        return jsonify(
            service="AutoDeploy Lab",
            status="running",
        )

    @app.get("/health")
    def health_check():
        return jsonify(status="healthy"), 200

    return app


if __name__ == "__main__":
    application = create_app()
    application.run(host="127.0.0.1", port=5000)
