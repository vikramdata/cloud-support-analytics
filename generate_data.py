"""
Generate synthetic Google-Cloud-style support case data for the
Cloud Support Analytics project (BigQuery + dbt + Looker Studio).

No public dataset contains real enterprise support tickets, so this script
simulates realistic patterns: weekday seasonality, incident spikes, response
times that depend on support tier and priority, and CSAT that drops when
cases are slow or escalated.

A small number of data quality defects are planted on purpose (documented
in DATA.md) so the dbt tests and the data quality dashboard page have
real issues to catch.

Usage:  python generate_data.py --out data --seed 42
"""

import argparse
import csv
import math
import os
import random
from datetime import datetime, timedelta, timezone

START = datetime(2025, 1, 1, tzinfo=timezone.utc)
END = datetime(2026, 9, 30, 23, 59, tzinfo=timezone.utc)

PRODUCTS = [
    # product_id, product_name, product_area, share of case volume
    ("P01", "Compute Engine", "Infrastructure", 0.18),
    ("P02", "Google Kubernetes Engine", "Infrastructure", 0.12),
    ("P03", "Cloud Run", "Serverless", 0.08),
    ("P04", "Cloud Storage", "Storage", 0.09),
    ("P05", "Cloud SQL", "Databases", 0.10),
    ("P06", "BigQuery", "Data Analytics", 0.13),
    ("P07", "Networking", "Networking", 0.10),
    ("P08", "IAM & Security", "Security", 0.07),
    ("P09", "Billing & Accounts", "Billing", 0.13),
]

TEAMS = ["Infrastructure", "Serverless", "Storage", "Databases",
         "Data Analytics", "Networking", "Security", "Billing"]
REGIONS = ["North America", "EMEA", "APAC", "LATAM"]
REGION_W = [0.45, 0.28, 0.20, 0.07]
TIERS = ["Standard", "Enhanced", "Premium"]
TIER_W = [0.60, 0.30, 0.10]
INDUSTRIES = ["Retail", "Financial Services", "Healthcare", "Media & Gaming",
              "Manufacturing", "Technology", "Public Sector", "Education"]
CHANNELS = ["Web", "Chat", "Phone"]

# Illustrative first-response targets in minutes (tier x priority).
SLA_TARGETS = {
    ("Premium", "P1"): 15, ("Premium", "P2"): 120, ("Premium", "P3"): 480, ("Premium", "P4"): 1440,
    ("Enhanced", "P1"): 60, ("Enhanced", "P2"): 240, ("Enhanced", "P3"): 960, ("Enhanced", "P4"): 2880,
    ("Standard", "P1"): 240, ("Standard", "P2"): 480, ("Standard", "P3"): 1440, ("Standard", "P4"): 4320,
}
PRIORITY_W = {"Standard": [0.03, 0.17, 0.45, 0.35],
              "Enhanced": [0.06, 0.24, 0.42, 0.28],
              "Premium":  [0.10, 0.30, 0.38, 0.22]}
# Median hours to resolve by priority.
RESOLVE_MEDIAN_H = {"P1": 6, "P2": 20, "P3": 52, "P4": 96}

N_CUSTOMERS = 1800
N_AGENTS = 140
BASE_DAILY_CASES = 85


def iso(dt):
    return dt.strftime("%Y-%m-%d %H:%M:%S") if dt else ""


def lognormal_minutes(median, sigma):
    return max(1.0, random.lognormvariate(math.log(median), sigma))


def make_customers():
    rows = []
    for i in range(1, N_CUSTOMERS + 1):
        signup = START - timedelta(days=random.randint(0, 1500))
        rows.append({
            "customer_id": f"C{i:05d}",
            "company_name": f"Customer {i:05d}",
            "industry": random.choice(INDUSTRIES),
            "region": random.choices(REGIONS, REGION_W)[0],
            "support_tier": random.choices(TIERS, TIER_W)[0],
            "customer_since": signup.strftime("%Y-%m-%d"),
        })
    return rows


def make_agents():
    rows = []
    for i in range(1, N_AGENTS + 1):
        rows.append({
            "agent_id": f"A{i:04d}",
            "agent_name": f"Agent {i:04d}",
            "team": TEAMS[(i - 1) % len(TEAMS)],
            "region": random.choices(REGIONS, REGION_W)[0],
            "level": random.choices(["L1", "L2", "L3"], [0.5, 0.35, 0.15])[0],
            "hire_date": (START - timedelta(days=random.randint(-300, 2000))).strftime("%Y-%m-%d"),
        })
    return rows


def incident_days():
    """A handful of outage-style days with a P1/P2 surge on one product."""
    days = {}
    for _ in range(7):
        d = START + timedelta(days=random.randint(0, (END - START).days))
        days[d.date()] = random.choice(PRODUCTS[:8])[0]
    return days


def daily_volume(day, idx):
    trend = 1 + 0.35 * idx / (END - START).days            # business growth
    weekday = [1.15, 1.12, 1.10, 1.08, 1.0, 0.45, 0.40][day.weekday()]
    month = 0.9 if day.month in (7, 8, 12) else 1.0       # holiday dips
    return max(5, int(random.gauss(BASE_DAILY_CASES * trend * weekday * month, 8)))


def main(out, seed):
    random.seed(seed)
    os.makedirs(out, exist_ok=True)

    customers = make_customers()
    agents = make_agents()
    agents_by_team = {t: [a for a in agents if a["team"] == t] for t in TEAMS}
    incidents = incident_days()
    product_lookup = {p[0]: p for p in PRODUCTS}

    cases, csat = [], []
    case_no = 0
    day = START
    idx = 0
    while day <= END:
        n = daily_volume(day, idx)
        surge_product = incidents.get(day.date())
        if surge_product:
            n += random.randint(120, 220)

        for _ in range(n):
            case_no += 1
            cust = random.choice(customers)
            tier = cust["support_tier"]

            if surge_product and random.random() < 0.55:
                product = product_lookup[surge_product]
                priority = random.choices(["P1", "P2"], [0.6, 0.4])[0]
            else:
                product = random.choices(PRODUCTS, [p[3] for p in PRODUCTS])[0]
                priority = random.choices(["P1", "P2", "P3", "P4"], PRIORITY_W[tier])[0]

            created = day + timedelta(minutes=random.randint(0, 1439))
            team_agents = agents_by_team[product[2]] if product[2] in agents_by_team else agents
            agent = random.choice(team_agents)

            # First response: usually inside target, worse on surge days and weekends.
            target = SLA_TARGETS[(tier, priority)]
            pressure = 1.0 + (1.6 if surge_product else 0) + (0.5 if created.weekday() >= 5 else 0)
            frt = lognormal_minutes(target * 0.45 * pressure, 0.7)
            first_response = created + timedelta(minutes=frt)

            escalated = random.random() < (0.22 if priority == "P1" else 0.08)
            resolve_h = lognormal_minutes(RESOLVE_MEDIAN_H[priority] * 60, 0.8) / 60
            if escalated:
                resolve_h *= 1.8
            resolved = first_response + timedelta(hours=resolve_h)

            if resolved > END:
                status = random.choice(["Open", "Pending Customer"])
                resolved = None
            else:
                status = "Closed"
            reopened = status == "Closed" and random.random() < 0.05

            cases.append({
                "case_id": f"CS{case_no:07d}",
                "customer_id": cust["customer_id"],
                "product_id": product[0],
                "priority": priority,
                "channel": random.choices(CHANNELS, [0.62, 0.25, 0.13])[0],
                "created_at": iso(created),
                "first_response_at": iso(first_response) if first_response <= END else "",
                "resolved_at": iso(resolved),
                "status": status,
                "assigned_agent_id": agent["agent_id"],
                "is_escalated": str(escalated).lower(),
                "is_reopened": str(reopened).lower(),
            })

            # ~30% of closed cases get a survey; slow or escalated cases score lower.
            if status == "Closed" and random.random() < 0.30:
                score = 4.6
                score -= 1.2 if frt > target else 0
                score -= 0.8 if escalated else 0
                score -= 0.7 if reopened else 0
                score -= 0.4 if resolve_h > RESOLVE_MEDIAN_H[priority] * 2 else 0
                score = min(5, max(1, round(random.gauss(score, 0.8))))
                csat.append({
                    "survey_id": f"SV{len(csat) + 1:07d}",
                    "case_id": cases[-1]["case_id"],
                    "submitted_at": iso(resolved + timedelta(hours=random.randint(1, 72))),
                    "csat_score": score,
                })
        day += timedelta(days=1)
        idx += 1

    plant_defects(cases, csat)

    write(out, "customers.csv", customers)
    write(out, "agents.csv", agents)
    write(out, "products.csv", [
        {"product_id": p[0], "product_name": p[1], "product_area": p[2]} for p in PRODUCTS])
    write(out, "sla_targets.csv", [
        {"support_tier": k[0], "priority": k[1], "first_response_target_minutes": v}
        for k, v in SLA_TARGETS.items()])
    write(out, "support_cases.csv", cases)
    write(out, "csat_responses.csv", csat)

    print(f"customers={len(customers)} agents={len(agents)} cases={len(cases)} "
          f"csat={len(csat)} incident_days={len(incidents)}")


def plant_defects(cases, csat):
    """Intentional data quality issues (see DATA.md)."""
    n = len(cases)
    for c in random.sample(cases, int(n * 0.004)):          # duplicate case rows
        cases.append(dict(c))
    for c in random.sample(cases, int(n * 0.002)):          # resolved before created
        if c["resolved_at"]:
            created = datetime.strptime(c["created_at"], "%Y-%m-%d %H:%M:%S")
            c["resolved_at"] = iso(created - timedelta(hours=random.randint(1, 48)))
    for c in random.sample(cases, int(n * 0.008)):          # missing agent
        c["assigned_agent_id"] = ""
    for s in random.sample(csat, int(len(csat) * 0.003)):   # out-of-range score
        s["csat_score"] = random.choice([0, 6, 10])
    for i in range(int(len(csat) * 0.002)):                  # orphan survey
        csat.append({"survey_id": f"SVX{i:05d}", "case_id": f"CS9{i:06d}",
                     "submitted_at": csat[i]["submitted_at"], "csat_score": 4})
    random.shuffle(cases)


def write(out, name, rows):
    with open(os.path.join(out, name), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    main(a.out, a.seed)
