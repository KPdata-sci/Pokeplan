import json, sys, re, os
def _clean(o):
    if isinstance(o,dict): return {k:(_clean(v) if k!="exampleResponse" else v) for k,v in o.items()}
    if isinstance(o,list): return [_clean(x) for x in o]
    if isinstance(o,str): return o.strip()
    return o
_load=json.load
def _jl(fp): return _clean(_load(fp))
src = sys.argv[1]; out = sys.argv[2]
groups = [("Resource Lists/Pagination","resource-lists"),("Berries","berries"),("Contests","contests"),("Currencies","currencies"),("Encounters","encounters"),("Evolution","evolution"),("Games","games"),("Items","items"),("Locations","locations"),("Machines","machines"),("Moves","moves"),("Pokémon","pokemon"),("Utility","utility")]
def tstr(t):
    if isinstance(t,str): return t
    if isinstance(t,dict):
        inner = tstr(t.get("of"))
        return f"{t['type']}<{inner}>" if inner else t["type"]
    return str(t)
def refs(t, acc):
    if isinstance(t,dict):
        if t.get("type") in ("NamedAPIResource","APIResource") and isinstance(t.get("of"),str): acc.add(t["of"])
        refs(t.get("of"),acc)
    return acc
res = {"source":"https://pokeapi.co/docs/v2 (rendered from github.com/PokeAPI/pokeapi.co src/docs/*.json)","base_url":"https://pokeapi.co/api/v2","groups":[]}
models_all = {}
for gname, f in groups:
    data = _jl(open(os.path.join(src,f+".json")))
    g = {"name":gname,"resources":[]}
    for r in data:
        req = r.get("exampleRequest")
        ep = None
        if req:
            m = re.match(r"/v2/([^/]+)/", req); ep = m.group(1) if m else None
        rr = {"name":r["name"],"endpoint":ep,"example_request":req,"description":r.get("description"),"models":[]}
        for mdl in r.get("responseModels") or []:
            fields=[]; rs=set()
            for fl in mdl.get("fields",[]):
                fields.append({"name":fl["name"],"type":tstr(fl.get("type")),"description":fl.get("description")}); refs(fl.get("type"),rs)
            rr["models"].append({"name":mdl["name"],"fields":fields,"references":sorted(rs)})
            models_all.setdefault(mdl["name"],[]).append(rr["name"])
        if req: rr["primary_model"] = rr["models"][0]["name"] if rr["models"] else None
        rr["example_response"] = r.get("exampleResponse")
        g["resources"].append(rr)
    res["groups"].append(g)
json.dump(res, open(out,"w"), indent=2, ensure_ascii=False)
eps=[r for g in res["groups"] for r in g["resources"] if r["endpoint"]]
print("groups",len(res["groups"]),"endpoints",len(eps),"models",len(models_all),"fields",sum(len(m["fields"]) for g in res["groups"] for r in g["resources"] for m in r["models"]))
for g in res["groups"]:
    print(g["name"], [ (r["endpoint"] or "-"+r["name"]) for r in g["resources"]])

# ---- pipeline-oriented flat endpoint index
model_to_ep = {}
for g in res["groups"]:
    for r in g["resources"]:
        if r["endpoint"] and r["endpoint"]!="{endpoint}" and r.get("primary_model") and "encounters" not in (r["example_request"] or ""):
            model_to_ep[r["primary_model"]] = r["endpoint"]
def model_refs(model_names, models_by_name, seen=None):
    out=set()
    for mn in model_names:
        for m in models_by_name.get(mn,[]): out |= set(m["references"])
    return out
REG={}
for gg in res["groups"]:
    for rr_ in gg["resources"]:
        for m in rr_["models"]: REG.setdefault(m["name"], m)
RAWT={}
for gname,f in groups:
    for r_ in _jl(open(os.path.join(src,f+".json"))):
        for m in r_.get("responseModels") or []:
            RAWT.setdefault(m["name"], [fl.get("type") for fl in m.get("fields",[])])
def walk(t, fks, seen):
    if isinstance(t,dict):
        if t.get("type") in ("NamedAPIResource","APIResource") and isinstance(t.get("of"),str):
            fks.add(t["of"]); return
        walk(t.get("of"), fks, seen)
    elif isinstance(t,str) and t in RAWT and t not in seen:
        seen.add(t)
        for ft in RAWT[t]: walk(ft, fks, seen)
eps=[]
for g in res["groups"]:
    for r in g["resources"]:
        if not r["endpoint"] or r["endpoint"]=="{endpoint}": continue
        refs_m=set(); seen=set([r.get("primary_model")])
        for ft in RAWT.get(r.get("primary_model"),[]): walk(ft, refs_m, seen)
        sub = r["example_request"].endswith("/encounters")
        eps.append({
          "endpoint": r["endpoint"] + ("/{id}/encounters" if sub else ""),
          "group": g["name"], "title": r["name"],
          "path": r["example_request"].replace("/v2","",1),
          "named": "{id or name}" in r["example_request"],
          "list_model": None if sub else ("NamedAPIResourceList" if "{id or name}" in r["example_request"] else "APIResourceList"),
          "primary_model": r["primary_model"],
          "returns_array": sub,
          "nested_models": [m["name"] for m in r["models"][1:]],
          "references_endpoints": sorted({model_to_ep[x] for x in refs_m if x in model_to_ep} - {r["endpoint"]}),
          "references_models_unresolved": sorted(x for x in refs_m if x not in model_to_ep),
        })
res["endpoints"]=eps
res["conventions"]={
 "methods":"GET only (consumption-only API)",
 "auth":"none",
 "rate_limit":"none since static hosting (Nov 2018); fair use policy applies, abusers IP-banned",
 "fair_use":["Locally cache resources whenever you request them","Be nice to fellow developers","Report security vulnerabilities responsibly"],
 "pagination":{"default_limit":20,"params":["limit","offset"],"example":"/api/v2/ability/?limit=60&offset=60","response_fields":["count","next","previous","results"]},
 "unnamed_endpoints":[e["endpoint"] for e in eps if not e["named"] and not e["returns_array"]],
 "url_placeholder":"Doc examples use $BASE_URL; real responses contain absolute https://pokeapi.co/api/v2/... URLs",
 "id_extraction":"Every NamedAPIResource/APIResource carries a url ending in /{id}/; parse the trailing integer to get a foreign key",
}
json.dump(res, open(out,"w"), indent=2, ensure_ascii=False)
print(len(eps), res["conventions"]["unnamed_endpoints"])
for e in eps: print(e["endpoint"], "->", e["references_endpoints"], e["references_models_unresolved"])
