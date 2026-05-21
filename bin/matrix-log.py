#!/usr/bin/env python3
"""
matrix-log.py - Send development logs to Matrix room

This script sends structured log messages to a Matrix room for
tracking deployments, task executions, tests, and other events
in the solti-podman collection.

Jackal Says:  This is a synapse matrix bot experiment. E2EE is important!

Usage:
    matrix-log.py message "Text message" [--level info|warning|error]
    matrix-log.py deployment <service> <host> <status> [options]
    matrix-log.py task <service> <host> <task_name> <status> [options]
    matrix-log.py test <service> <platform> <status> [options]

Options:
    --duration SECONDS      Execution duration
    --details KEY=VALUE     Additional metadata (repeatable)
    --tests PASSED/TOTAL    Test results
    --level LEVEL           Message severity (info|warning|error)
    --dry-run               Print message without sending
    --config FILE           Config file path (default: data/matrix-logger.conf)
    --token TOKEN           Override access token
    --room ROOM_ID          Override room ID
    --homeserver URL        Override homeserver URL

Configuration:
    Create data/matrix-logger.conf with:
    {
      "homeserver_url": "http://matrix-svr.example.com:8008",
      "access_token": "YOUR_TOKEN",
      "room_id": "!abc123:example.com"
    }

    Or set environment variables:
      MATRIX_HOMESERVER, MATRIX_TOKEN, MATRIX_ROOM_ID

Examples:
    # Simple message
    matrix-log.py message "Deployment started"

    # Deployment event
    matrix-log.py deployment redis monitor11 success \
      --duration 45 --details containers=2 ports=6379

    # Task execution
    matrix-log.py task redis monitor11 verify success --duration 5.2

    # Test result
    matrix-log.py test redis debian12 success --duration 180 --tests "5/5"
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


class MatrixLogger:
    """Send log messages to Matrix room"""

    def __init__(self, homeserver_url, access_token, room_id):
        self.homeserver_url = homeserver_url.rstrip("/")
        self.access_token = access_token
        self.room_id = room_id

    @staticmethod
    def _sanitize_for_matrix(obj):
        """Sanitize values for Matrix JSON compatibility (no floats)"""
        if isinstance(obj, dict):
            return {k: MatrixLogger._sanitize_for_matrix(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [MatrixLogger._sanitize_for_matrix(v) for v in obj]
        elif isinstance(obj, float):
            # Matrix doesn't like floats - convert to int if whole number, else string
            if obj == int(obj):
                return int(obj)
            else:
                return str(round(obj, 2))  # Convert to string representation
        else:
            return obj

    def send_message(self, text, json_data=None, dry_run=False):
        """
        Send message to Matrix room

        Args:
            text: Human-readable message text (supports markdown)
            json_data: Optional structured data for machine parsing
            dry_run: If True, print message without sending

        Returns:
            dict: Response from Matrix API or None if dry_run
        """
        # Build message content
        content = {
            "msgtype": "m.text",
            "body": text,
            "format": "org.matrix.custom.html",
            "formatted_body": self._markdown_to_html(text),
        }

        # Add structured data if provided (sanitized for Matrix)
        if json_data:
            content["dev.solti.log_data"] = self._sanitize_for_matrix(json_data)

        if dry_run:
            print("DRY RUN - Would send to Matrix:")
            print(f"Room: {self.room_id}")
            print(f"Text:\n{text}")
            if json_data:
                print(f"JSON:\n{json.dumps(json_data, indent=2)}")
            return None

        # Send to Matrix
        url = f"{self.homeserver_url}/_matrix/client/v3/rooms/{self.room_id}/send/m.room.message"

        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
        }

        data = json.dumps(content).encode("utf-8")

        try:
            req = urllib.request.Request(url, data=data, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=10) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8") if e.fp else ""
            raise Exception(f"HTTP {e.code}: {error_body}")
        except urllib.error.URLError as e:
            raise Exception(f"Network error: {e.reason}")

    @staticmethod
    def _markdown_to_html(text):
        """Basic markdown to HTML conversion for Matrix"""
        # This is a simplified version - Matrix supports markdown
        html = text
        # Bold
        html = html.replace("**", "<strong>").replace("**", "</strong>")
        # Code
        html = html.replace("`", "<code>").replace("`", "</code>")
        # Newlines
        html = html.replace("\n", "<br/>")
        return html


class EventFormatter:
    """Format different event types for logging"""

    @staticmethod
    def format_deployment(service, host, status, duration=None, details=None):
        """Format deployment event"""
        # Status emoji
        status_emoji = {
            "success": "✅",
            "failure": "❌",
            "warning": "⚠️",
            "info": "ℹ️",
        }.get(status.lower(), "📝")

        # Build human-readable message
        lines = [
            f"🚀 **Deploy: {service}@{host}**",
            f"{status_emoji} Status: **{status.upper()}**",
        ]

        if duration is not None:
            lines.append(f"⏱️ Duration: {duration:.1f}s")

        if details:
            for key, value in details.items():
                lines.append(f"  {key}: {value}")

        text = "\n".join(lines)

        # Build structured data
        json_data = {
            "event_type": "deployment",
            "service": service,
            "host": host,
            "status": status.lower(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user": os.environ.get("USER", "unknown"),
        }

        if duration is not None:
            json_data["duration_seconds"] = duration

        if details:
            json_data["details"] = details

        return text, json_data

    @staticmethod
    def format_task(service, host, task_name, status, duration=None, details=None):
        """Format task execution event"""
        status_emoji = {
            "success": "✅",
            "failure": "❌",
            "warning": "⚠️",
            "info": "ℹ️",
        }.get(status.lower(), "📝")

        lines = [
            f"⚙️ **Task: {service}/{task_name}@{host}**",
            f"{status_emoji} Status: **{status.upper()}**",
        ]

        if duration is not None:
            lines.append(f"⏱️ Duration: {duration:.1f}s")

        if details:
            for key, value in details.items():
                lines.append(f"  {key}: {value}")

        text = "\n".join(lines)

        json_data = {
            "event_type": "task",
            "service": service,
            "host": host,
            "task_name": task_name,
            "status": status.lower(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user": os.environ.get("USER", "unknown"),
        }

        if duration is not None:
            json_data["duration_seconds"] = duration

        if details:
            json_data["details"] = details

        return text, json_data

    @staticmethod
    def format_test(service, platform, status, duration=None, tests=None, details=None):
        """Format test event"""
        status_emoji = {
            "success": "✅",
            "failure": "❌",
            "warning": "⚠️",
            "info": "ℹ️",
        }.get(status.lower(), "📝")

        lines = [
            f"🧪 **Test: {service} on {platform}**",
            f"{status_emoji} Status: **{status.upper()}**",
        ]

        if duration is not None:
            lines.append(f"⏱️ Duration: {duration:.1f}s")

        if tests:
            lines.append(f"📊 Tests: {tests}")

        if details:
            for key, value in details.items():
                lines.append(f"  {key}: {value}")

        text = "\n".join(lines)

        json_data = {
            "event_type": "test",
            "service": service,
            "platform": platform,
            "status": status.lower(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user": os.environ.get("USER", "unknown"),
        }

        if duration is not None:
            json_data["duration_seconds"] = duration

        if tests:
            json_data["tests"] = tests

        if details:
            json_data["details"] = details

        return text, json_data

    @staticmethod
    def format_message(message, level="info"):
        """Format simple text message"""
        level_emoji = {
            "info": "ℹ️",
            "warning": "⚠️",
            "error": "❌",
        }.get(level.lower(), "📝")

        text = f"{level_emoji} {message}"

        json_data = {
            "event_type": "message",
            "level": level.lower(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user": os.environ.get("USER", "unknown"),
            "message": message,
        }

        return text, json_data


def load_config(config_path=None):
    """Load configuration from file or environment"""
    config = {}

    # Try config file
    if config_path is None:
        # Default location relative to script
        script_dir = Path(__file__).parent.parent
        config_path = script_dir / "data" / "matrix-logger.conf"

    if config_path and Path(config_path).exists():
        with open(config_path, "r") as f:
            config = json.load(f)

    # Environment variables override config file
    if "MATRIX_HOMESERVER" in os.environ:
        config["homeserver_url"] = os.environ["MATRIX_HOMESERVER"]
    if "MATRIX_TOKEN" in os.environ:
        config["access_token"] = os.environ["MATRIX_TOKEN"]
    if "MATRIX_ROOM_ID" in os.environ:
        config["room_id"] = os.environ["MATRIX_ROOM_ID"]

    return config


def parse_details(details_list):
    """Parse KEY=VALUE pairs into dict"""
    if not details_list:
        return {}

    result = {}
    for item in details_list:
        if "=" in item:
            key, value = item.split("=", 1)
            result[key] = value
        else:
            result[item] = True
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Send structured logs to Matrix room",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Subcommands
    subparsers = parser.add_subparsers(dest="command", required=True)

    # message command
    msg_parser = subparsers.add_parser("message", help="Send text message")
    msg_parser.add_argument("text", help="Message text")
    msg_parser.add_argument(
        "--level",
        default="info",
        choices=["info", "warning", "error"],
        help="Message severity",
    )

    # deployment command
    deploy_parser = subparsers.add_parser("deployment", help="Log deployment event")
    deploy_parser.add_argument("service", help="Service name")
    deploy_parser.add_argument("host", help="Target host")
    deploy_parser.add_argument(
        "status",
        choices=["success", "failure", "warning", "info"],
        help="Deployment status",
    )
    deploy_parser.add_argument(
        "--duration", type=float, help="Execution duration in seconds"
    )
    deploy_parser.add_argument(
        "--details",
        action="append",
        metavar="KEY=VALUE",
        help="Additional metadata (repeatable)",
    )

    # task command
    task_parser = subparsers.add_parser("task", help="Log task execution")
    task_parser.add_argument("service", help="Service name")
    task_parser.add_argument("host", help="Target host")
    task_parser.add_argument("task_name", help="Task name")
    task_parser.add_argument(
        "status", choices=["success", "failure", "warning", "info"], help="Task status"
    )
    task_parser.add_argument(
        "--duration", type=float, help="Execution duration in seconds"
    )
    task_parser.add_argument(
        "--details",
        action="append",
        metavar="KEY=VALUE",
        help="Additional metadata (repeatable)",
    )

    # test command
    test_parser = subparsers.add_parser("test", help="Log test event")
    test_parser.add_argument("service", help="Service name")
    test_parser.add_argument("platform", help="Test platform (debian12, rocky9, etc)")
    test_parser.add_argument(
        "status", choices=["success", "failure", "warning", "info"], help="Test status"
    )
    test_parser.add_argument(
        "--duration", type=float, help="Execution duration in seconds"
    )
    test_parser.add_argument("--tests", help='Test results (e.g., "5/5")')
    test_parser.add_argument(
        "--details",
        action="append",
        metavar="KEY=VALUE",
        help="Additional metadata (repeatable)",
    )

    # Global options
    parser.add_argument(
        "--dry-run", action="store_true", help="Print message without sending"
    )
    parser.add_argument("--config", help="Config file path")
    parser.add_argument("--token", help="Override access token")
    parser.add_argument("--room", help="Override room ID")
    parser.add_argument("--homeserver", help="Override homeserver URL")

    args = parser.parse_args()

    # Load configuration
    try:
        config = load_config(args.config)
    except Exception as e:
        print(f"Error loading config: {e}", file=sys.stderr)
        config = {}

    # CLI overrides
    if args.token:
        config["access_token"] = args.token
    if args.room:
        config["room_id"] = args.room
    if args.homeserver:
        config["homeserver_url"] = args.homeserver

    # Validate configuration (skip in dry-run mode)
    if not args.dry_run:
        required = ["homeserver_url", "access_token", "room_id"]
        missing = [k for k in required if k not in config]
        if missing:
            print(
                f"Error: Missing configuration: {', '.join(missing)}", file=sys.stderr
            )
            print(
                "Create data/matrix-logger.conf or set environment variables",
                file=sys.stderr,
            )
            print("Run: mylab/bin/setup-logger-config.sh", file=sys.stderr)
            return 1

    # Format message based on command
    formatter = EventFormatter()

    if args.command == "message":
        text, json_data = formatter.format_message(args.text, args.level)

    elif args.command == "deployment":
        details = parse_details(args.details)
        text, json_data = formatter.format_deployment(
            args.service, args.host, args.status, args.duration, details
        )

    elif args.command == "task":
        details = parse_details(args.details)
        text, json_data = formatter.format_task(
            args.service, args.host, args.task_name, args.status, args.duration, details
        )

    elif args.command == "test":
        details = parse_details(args.details)
        text, json_data = formatter.format_test(
            args.service, args.platform, args.status, args.duration, args.tests, details
        )

    else:
        print(f"Unknown command: {args.command}", file=sys.stderr)
        return 1

    # Send message
    try:
        if args.dry_run:
            logger = MatrixLogger("", "", "")
            logger.send_message(text, json_data, dry_run=True)
        else:
            logger = MatrixLogger(
                config["homeserver_url"], config["access_token"], config["room_id"]
            )
            response = logger.send_message(text, json_data)
            if response:
                print(f"✓ Message sent: {response.get('event_id', 'unknown')}")
        return 0

    except Exception as e:
        print(f"Error sending message: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
