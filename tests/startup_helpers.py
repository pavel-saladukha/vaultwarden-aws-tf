"""Render startup with dummy inputs. Never run its main function in tests."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def write_startup(directory):
    source = (ROOT / "data/init.sh").read_text()
    inputs = {
        "full_domain_name": "test-unique.example.invalid",
        "hosted_zone_id": "ZTESTONLY",
        "s3_configs": "upgrade-test-dummy-configs",
        "s3_backups": "upgrade-test-dummy-backups",
    }
    source = re.sub(
        r"(?<!\$)\$\{(\w+)\}",
        lambda match: inputs.get(match[1], "dummy-" + match[1]),
        source,
    )
    source = source.replace("$${", "${")
    path = Path(directory) / "startup.sh"
    path.write_text(source)
    return path
