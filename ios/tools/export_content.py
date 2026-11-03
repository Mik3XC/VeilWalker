#!/usr/bin/env python3
"""Exports the journey, outlaw and peak content from the Android Kotlin sources to JSON, so the iOS app loads the
exact same copy (handoff §7: "export it to shared JSON that both apps load"). Android keeps its Kotlin for now.

Usage: export_content.py <android repo root> <output dir>

Parses the Kotlin constructor calls directly (strings, + concatenation, numbers, listOf, named args), so no copy
is retyped by hand. Fails loudly on anything it doesn't understand, and checks the counts the handoff promises.
"""
import json
import re
import sys
from pathlib import Path

TOKEN = re.compile(r'''
    (?P<ws>\s+|//[^\n]*|/\*.*?\*/)
  | (?P<str>"(?:\\.|[^"\\])*")
  | (?P<num>\d[\d_]*(?:\.\d+)?)
  | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[^\s\w"])
''', re.S | re.X)


def tokens(src):
    pos, out = 0, []
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m:
            raise SyntaxError(f"can't tokenize at {src[pos:pos + 40]!r}")
        pos = m.end()
        if m.lastgroup != "ws":
            out.append((m.lastgroup, m.group()))
    return out


def unescape(s):
    body = s[1:-1]
    if "$" in body.replace("\\$", ""):
        raise ValueError(f"string template not supported: {s}")
    return re.sub(r'\\(u[0-9a-fA-F]{4}|.)', lambda m: chr(int(m.group(1)[1:], 16)) if m.group(1)[0] == "u"
                  else {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)


class Parser:
    """Just enough Kotlin expression grammar for the content files."""

    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, value=None):
        tok = self.t[self.i]
        if value is not None and tok[1] != value:
            raise SyntaxError(f"expected {value!r}, got {tok[1]!r} near {self.t[self.i - 3:self.i + 3]}")
        self.i += 1
        return tok

    def expr(self):
        v = self.atom()
        while self.peek()[1] == "+":
            self.take("+")
            rhs = self.atom()
            if not (isinstance(v, str) and isinstance(rhs, str)):
                raise SyntaxError("only string + string is supported")
            v += rhs
        return v

    def atom(self):
        kind, val = self.peek()
        if val == "-" and self.peek(1)[0] == "num":
            self.take("-")
            return -self.atom()
        if kind == "str":
            self.take()
            return unescape(val)
        if kind == "num":
            self.take()
            return float(val.replace("_", "")) if "." in val else int(val.replace("_", ""))
        if val == "(":
            # A computed value such as (NorthStarRoute.lengthM / 1000).toInt(): keep it as a marker.
            depth, start = 0, self.i
            while True:
                _, v = self.take()
                depth += {"(": 1, ")": -1}.get(v, 0)
                if depth == 0:
                    break
            while self.peek()[1] == "." and self.peek(1)[0] == "id":
                self.take(); self.take()
                if self.peek()[1] == "(":
                    self.take("("); self.take(")")
            return {"$expr": " ".join(v for _, v in self.t[start:self.i])}
        if kind == "id":
            name = self.take()[1]
            while self.peek()[1] == "." and self.peek(1)[0] == "id":
                self.take(".")
                name += "." + self.take()[1]
            if self.peek()[1] == "(":
                return {"$call": name, **self.args()}
            return {"$ref": name}
        raise SyntaxError(f"unexpected {val!r}")

    def args(self):
        self.take("(")
        pos, named = [], {}
        while self.peek()[1] != ")":
            if self.peek()[0] == "id" and self.peek(1)[1] == "=":
                key = self.take()[1]
                self.take("=")
                named[key] = self.expr()
            else:
                pos.append(self.expr())
            if self.peek()[1] == ",":
                self.take(",")
        self.take(")")
        return {"args": pos, "named": named}


def calls_in(src, start_marker, fn):
    """Parses `start_marker listOf(...)` and returns the list's call items whose function is `fn`."""
    toks = tokens(src[src.index(start_marker) + len(start_marker):])
    p = Parser(toks)
    lst = p.expr()
    assert lst["$call"] == "listOf", lst
    items = lst["args"]
    assert all(isinstance(x, dict) and x.get("$call") == fn for x in items), "unexpected list item"
    return items


def bind(call, params):
    """Positional + named args → dict, by the Kotlin parameter order."""
    out = dict(zip(params, call["args"]))
    out.update(call["named"])
    return out


def strings(lst):
    assert lst["$call"] == "listOf"
    assert all(isinstance(s, str) for s in lst["args"])
    return lst["args"]


def const(src, name):
    return unescape(re.search(rf'const val {name} = ("(?:\\.|[^"\\])*")', src).group(1))


def main(root, out_dir):
    route_dir = Path(root) / "core/route/src/main/java/org/trailbound/core/route"
    north = (route_dir / "NorthStarRoute.kt").read_text()
    journeys_src = (route_dir / "Journeys.kt").read_text()
    outlaws_src = (route_dir / "Outlaws.kt").read_text()
    peaks_src = (route_dir / "Peaks.kt").read_text()

    # The walkable route: geometry + postcards.
    route_call = Parser(tokens(north[north.index("val NorthStarRoute =") + len("val NorthStarRoute ="):])).expr()
    r = bind(route_call, ["id", "title", "subtitle", "milestones"])
    milestones = []
    for m in r["milestones"]["args"]:
        mm = bind(m, ["name", "point", "postcard"])
        lat, lng = mm["point"]["args"]
        milestones.append({"name": mm["name"], "lat": lat, "lng": lng, "postcard": mm["postcard"]})
    routes = [{"id": r["id"], "title": r["title"], "subtitle": r["subtitle"], "milestones": milestones}]

    # Walk for Freedom catalogue.
    journey_params = ["id", "title", "subtitle", "km", "postcards", "teaser", "unlock", "route", "facts", "why", "card"]
    freedom = []
    for c in calls_in(journeys_src, "private val freedom: List<Journey> =", "Journey"):
        j = bind(c, journey_params)
        entry = {"id": j["id"]}
        if j.get("route") is not None:
            # Title, subtitle, km and postcard count come from the route itself.
            assert j["route"] == {"$ref": "NorthStarRoute"}, j["route"]
            entry["route"] = r["id"]
        else:
            for k in ("title", "subtitle", "km", "postcards"):
                assert not isinstance(j[k], dict), (j["id"], k, j[k])
                entry[k] = j[k]
        for k in ("teaser", "unlock"):
            entry[k] = j[k]
        entry["facts"] = strings(j["facts"]) if "facts" in j else []
        entry["why"] = j.get("why", "")
        freedom.append(entry)

    # Outlaws on Foot.
    vols = {"VOL_1": const(outlaws_src, "VOL_1"), "VOL_2": const(outlaws_src, "VOL_2")}
    outlaws = []
    for c in calls_in(outlaws_src, "val all: List<Journey> =", "outlaw"):
        o = bind(c, ["id", "title", "subtitle", "card", "teaser", "facts", "why"])
        card = bind(o["card"], ["name", "collection", "rarity", "steps", "quote"])
        outlaws.append({
            "id": o["id"], "title": o["title"], "subtitle": o["subtitle"],
            "card": {
                "name": card["name"],
                "collection": vols[card["collection"]["$ref"]],
                "rarity": card["rarity"]["$ref"].removeprefix("Rarity."),
                "steps": card["steps"],
                "quote": card["quote"],
            },
            "teaser": o["teaser"], "facts": strings(o["facts"]), "why": o["why"],
        })

    # Hidden Peaks.
    peaks = []
    for c in calls_in(peaks_src, "val all: List<Peak> =", "Peak"):
        p = bind(c, ["id", "name", "region", "heightM", "quote", "facts", "demon"])
        peaks.append({"id": p["id"], "name": p["name"], "region": p["region"], "heightM": p["heightM"],
                      "quote": p["quote"], "facts": strings(p["facts"]), "demon": p.get("demon", {"$ref": "false"}) == {"$ref": "true"}})

    assert len(freedom) == 20, len(freedom)
    assert len(outlaws) == 15, len(outlaws)
    assert len(peaks) == 11, len(peaks)
    assert len(milestones) == 12, len(milestones)
    assert sum(p["demon"] for p in peaks) == 1

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    doc = {
        "version": 1,
        "source": "generated by tools/export_content.py from the Android Kotlin content; edit the source, not this file",
        "routes": routes,
        "freedom": freedom,
        "outlaws": {"volumes": list(vols.values()), "cards": outlaws},
        "peaks": {"title": const(peaks_src, "TITLE"), "all": peaks},
    }
    (out / "content.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    print(f"routes 1 ({len(milestones)} postcards) · freedom {len(freedom)} · outlaws {len(outlaws)} · peaks {len(peaks)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
