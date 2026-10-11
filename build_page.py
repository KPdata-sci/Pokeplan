import json, sys
d = json.load(open(sys.argv[1]))
# compact data for the page
groups=[]
for g in d["groups"]:
    gg={"n":g["name"],"r":[]}
    for r in g["resources"]:
        gg["r"].append({"t":r["name"],"ep":r["endpoint"],"req":r["example_request"],"desc":r["description"],
          "m":[{"n":m["name"],"f":[[f["name"],f["type"],f["description"]] for f in m["fields"]]} for m in r["models"]],
          "ex":r["example_response"]})
    groups.append(gg)
eps={e["endpoint"]:e for e in d["endpoints"]}
indeg={}
for e in d["endpoints"]:
    for x in e["references_endpoints"]: indeg[x]=indeg.get(x,0)+1
import os
notes_path=os.path.join(os.path.dirname(os.path.abspath(__file__)),"domain","endpoint_notes.json")
notes=json.load(open(notes_path)) if os.path.exists(notes_path) else {}
data={"groups":groups,"eps":eps,"indeg":indeg,"conv":d["conventions"],"notes":notes}
tpl=open(sys.argv[2]).read()
blob=json.dumps(data,ensure_ascii=False).replace("</","<\\/")
open(sys.argv[3],"w").write(tpl.replace("__DATA__",blob))
print(len(blob), sorted(indeg.items(), key=lambda x:-x[1])[:8])
