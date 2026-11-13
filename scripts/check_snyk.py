import json
import sys

REPORTS = [
    "reports/snyk-production.json",
    "reports/snyk-development.json",
]

critical = []

for filename in REPORTS:
    try:
        with open(filename, encoding="utf-8") as report:
            data = json.load(report)
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR reading {filename}: {error}")
        sys.exit(2)

    vulnerabilities = data.get("vulnerabilities", [])

    for vulnerability in vulnerabilities:
        if vulnerability.get("severity", "").lower() == "critical":
            critical.append((filename, vulnerability))

print(f"Critical vulnerabilities found: {len(critical)}")

for filename, vulnerability in critical:
    print(
        f"{filename}: "
        f"{vulnerability.get('id')} - "
        f"{vulnerability.get('title')}"
    )

if critical:
    print("SNYK SECURITY GATE: FAILED")
    sys.exit(1)

print("SNYK SECURITY GATE: PASSED")
