#!/usr/bin/env python3
"""Check the image selector without running Docker or contacting Docker Hub."""

import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import textwrap


root = Path(__file__).resolve().parents[1]
workflow = (root / ".github/workflows/docker.yml").read_text()
start = workflow.index("          python3 - <<'PY' >> \"$GITHUB_OUTPUT\"\n")
script = workflow[start:].split("\n          PY\n", 1)[0].split("\n", 1)[1]
script = textwrap.dedent(script)
function = next(node for node in ast.parse(script).body if isinstance(node, ast.FunctionDef) and node.name == "meaningful_diff")
namespace = {}
exec(compile(ast.Module(body=[function], type_ignores=[]), "<selector>", "exec"), namespace)
meaningful_diff = namespace["meaningful_diff"]
assert not meaningful_diff("+ # changed comment\n- # old comment\n")
assert not meaningful_diff("+   \n")
assert meaningful_diff("+RUN echo changed\n")
assert meaningful_diff("new file mode 100644\n")


def select(event, source_35="false"):
    env = os.environ.copy()
    env.update(EVENT_NAME=event, REF="refs/heads/master", BUILD_SOURCE_POSTGIS_35=source_35)
    output = subprocess.check_output([sys.executable, "-c", script], cwd=root, env=env, text=True)
    values = dict(line.split("=", 1) for line in output.splitlines())
    return values, {(item["version"], item["variant"]) for item in json.loads(values["images"])["include"]}


push, targets = select("push")
assert push["latest_version"] == "18-3.6"
assert targets and all(version.endswith("-master") for version, _ in targets)

_, targets = select("workflow_dispatch")
assert ("17-3.5", "default") in targets
assert ("18-3.5", "default") not in targets
assert ("17-3.5", "alpine") not in targets

_, opted_in = select("workflow_dispatch", "true")
assert ("18-3.5", "default") in opted_in
assert ("17-3.5", "alpine") in opted_in

print("workflow image selection checks passed")
