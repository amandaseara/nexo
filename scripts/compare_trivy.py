import json
from collections import Counter
from pathlib import Path

REPORTS = Path("reports/image-analysis")

def summarize(filename):
    with open(REPORTS / filename, encoding="utf-8") as file:
        data = json.load(file)

    summary = Counter()

    for result in data.get("Results", []):
        for vulnerability in result.get("Vulnerabilities", []):
            severity = vulnerability.get("Severity")

            if severity in ("HIGH", "CRITICAL"):
                summary[severity] += 1

    return summary

def main():
    initial = summarize("trivy-initial.json")
    final = summarize("trivy-final.json")

    print("NEXO - Comparación de vulnerabilidades")
    print("-" * 48)
    print(f"{'Severidad':<15}{'Inicial':>10}{'Final':>10}")
    print("-" * 48)

    for severity in ("HIGH", "CRITICAL"):
        print(
            f"{severity:<15}"
            f"{initial[severity]:>10}"
            f"{final[severity]:>10}"
        )

    print("-" * 48)

    initial_total = sum(initial.values())
    final_total = sum(final.values())

    print(f"{'TOTAL':<15}{initial_total:>10}{final_total:>10}")

    if initial_total:
        reduction = (initial_total - final_total) / initial_total * 100
        print(f"\nVariación de hallazgos: {-reduction:+.1f}%")

if __name__ == "__main__":
    main()
