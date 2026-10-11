# Turn the PokeAPI static JSON tree (github.com/PokeAPI/api-data) into a CSV
# shaped like raw.api_response, so a whole crawl can be landed with one COPY.
import csv, hashlib, json, os, sys
root, out = sys.argv[1], sys.argv[2]
n = 0
with open(out, "w", newline="") as fh:
    w = csv.writer(fh)
    for ep in sorted(os.listdir(root)):
        d = os.path.join(root, ep)
        if not os.path.isdir(d):
            continue
        for rid in os.listdir(d):
            f = os.path.join(d, rid, "index.json")
            if not rid.isdigit() or not os.path.exists(f):
                continue
            payload = json.dumps(json.load(open(f)), separators=(",", ":"), ensure_ascii=False)
            obj = json.loads(payload)
            name = obj.get("name") if isinstance(obj, dict) else None
            w.writerow([ep, int(rid), name, f"/api/v2/{ep}/{rid}/", payload,
                        hashlib.sha256(payload.encode()).hexdigest()])
            n += 1
print(n, "rows")
