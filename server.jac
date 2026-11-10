import from byllm.lib { Model }

glob llm = Model(model_name="anthropic/claude-haiku-5-5");

enum Amalgamation { WHOLE_ORE, CONCENTRATE, MERCURY_FREE, UNKNOWN }
enum Burning { OPEN_BURNING, RETORT, NONE, UNKNOWN }

obj Batch {
    has ore_kg: float;
    has mercury_g: float;
    has amalgamation: Amalgamation;
    has burning: Burning;
}

obj Estimate {
    has to_air_g: float;
    has to_tailings_g: float;
    has risk: str;
    has assumed: bool;
}

# ---------------------------------------------------------------
# LOSS FACTORS - ILLUSTRATIVE ASSUMPTIONS.
# These values are not yet validated against field data or published
# measurements. Replace them with cited figures before any real-world use.
# ---------------------------------------------------------------
# Share of the mercury used that ends up in tailings (soil/water).
# The rest stays in the amalgam and is released when it is burned.
glob TAILINGS_SHARE: dict[Amalgamation, float] = {
    Amalgamation.WHOLE_ORE: 0.75,
    Amalgamation.CONCENTRATE: 0.10,
    Amalgamation.MERCURY_FREE: 0.0,
    Amalgamation.UNKNOWN: 0.75
};
# Share of mercury vapour a retort captures (not released to air).
glob RETORT_CAPTURE: float = 0.90;

# ---------- Agent 1: Intake (NLP) ----------
"""Extract mining batch details from a miner's message in Swahili or English.
If the message does not mention how the amalgam was burned, use UNKNOWN."""
def extract_batch(message: str) -> Batch by llm(temperature=None);

# ---------- Agent 2: Estimator (rules, no AI guessing) ----------
def estimate(b: Batch) -> Estimate {
    assumed: bool = (b.amalgamation == Amalgamation.UNKNOWN) or (b.burning == Burning.UNKNOWN);

    to_tailings: float = b.mercury_g * TAILINGS_SHARE[b.amalgamation];
    in_amalgam: float = b.mercury_g - to_tailings;

    # Open burning or unknown: assume all mercury in the amalgam goes to air.
    to_air: float = in_amalgam;
    if b.burning == Burning.RETORT {
        to_air = in_amalgam * (1 - RETORT_CAPTURE);
    }
    if b.burning == Burning.NONE {
        to_air = 0.0;
    }

    risk: str = "LOW";
    if (b.amalgamation == Amalgamation.WHOLE_ORE) or (b.burning == Burning.OPEN_BURNING) {
        risk = "HIGH";
    }
    if risk == "LOW" and assumed {
        risk = "MEDIUM";
    }

    return Estimate(
        to_air_g=int(to_air * 10 + 0.5) / 10,
        to_tailings_g=int(to_tailings * 10 + 0.5) / 10,
        risk=risk,
        assumed=assumed
    );
}

# ---------- Agent 3: Advisor (explains in plain Swahili) ----------
"""Explain to an artisanal miner, in simple Swahili and in 2-3 short sentences,
how much mercury this batch released to air and to tailings, and suggest
one practical step to reduce mercury loss next time. If assumed is true,
say that some details were missing and ask the miner to report them."""
def advise(batch: Batch, est: Estimate) -> str by llm(temperature=None);

# ---------- Cooperative graph ----------
node Cooperative {
    has name: str;
}

node Miner {
    has name: str;
}

node BatchRecord {
    has message: str;
    has mercury_g: float;
    has to_air_g: float;
    has to_tailings_g: float;
    has risk: str;
}

# ---------- Agent 4: Impact (walks the graph and adds up) ----------
# "Avoided" = mercury that stayed out of air/tailings compared with the
# worst case where all mercury used is lost (whole-ore + open burning).
walker ImpactReport {
    has used_g: float = 0.0;
    has air_g: float = 0.0;
    has tailings_g: float = 0.0;
    has batches: int = 0;
    has high_risk: int = 0;

    can start with Cooperative entry {
        visit [-->];
    }

    can each_miner with Miner entry {
        visit [-->];
    }

    can each_batch with BatchRecord entry {
        self.used_g += here.mercury_g;
        self.air_g += here.to_air_g;
        self.tailings_g += here.to_tailings_g;
        self.batches += 1;
        if here.risk == "HIGH" {
            self.high_risk += 1;
        }
    }
}

# ---------- Web API (used by the page in assets/index.html) ----------
def get_coop() -> Cooperative {
    for c in [root --> [?:Cooperative]] {
        return c;
    }
    return (root ++> Cooperative(name="Ushirika wa Wachimbaji - Demo"))[0];
}

def impact_summary(coop: Cooperative) -> dict {
    used: float = 0.0;
    air: float = 0.0;
    tailings: float = 0.0;
    batches = 0;
    high = 0;
    miner_rows = [];
    for m in [coop --> [?:Miner]] {
        m_used: float = 0.0;
        m_air: float = 0.0;
        m_tail: float = 0.0;
        m_batches = 0;
        m_high = 0;
        for r in [m --> [?:BatchRecord]] {
            used += r.mercury_g;
            air += r.to_air_g;
            tailings += r.to_tailings_g;
            batches += 1;
            m_used += r.mercury_g;
            m_air += r.to_air_g;
            m_tail += r.to_tailings_g;
            m_batches += 1;
            if r.risk == "HIGH" {
                high += 1;
                m_high += 1;
            }
        }
        miner_rows.append({
            "name": m.name,
            "batches": m_batches,
            "used_g": int(m_used * 10 + 0.5) / 10,
            "air_g": int(m_air * 10 + 0.5) / 10,
            "tailings_g": int(m_tail * 10 + 0.5) / 10,
            "high_risk": m_high
        });
    }
    return {
        "cooperative": coop.name,
        "batches": batches,
        "high_risk": high,
        "used_g": int(used * 10 + 0.5) / 10,
        "air_g": int(air * 10 + 0.5) / 10,
        "tailings_g": int(tailings * 10 + 0.5) / 10,
        "avoided_g": int((used - air - tailings) * 10 + 0.5) / 10,
        "miners": miner_rows
    };
}

# ---------- What-if: what would switching method save? ----------
def switch_saving(b: Batch) -> dict {
    cur = estimate(b);
    better = Batch(
        ore_kg=b.ore_kg,
        mercury_g=b.mercury_g,
        amalgamation=Amalgamation.CONCENTRATE,
        burning=Burning.RETORT
    );
    after = estimate(better);
    saved: float = (cur.to_air_g + cur.to_tailings_g) - (after.to_air_g + after.to_tailings_g);
    if saved < 0 {
        saved = 0.0;
    }
    return {
        "method": "concentrate + retort",
        "to_air_g": after.to_air_g,
        "to_tailings_g": after.to_tailings_g,
        "saved_g": int(saved * 10 + 0.5) / 10
    };
}

walker:pub analyse_batch {
    has miner: str;
    has message: str;

    can run with Root entry {
        coop = get_coop();
        b = extract_batch(self.message);
        e = estimate(b);

        miners = [x for x in [coop --> [?:Miner]] if x.name == self.miner];
        if not miners {
            miners = coop ++> Miner(name=self.miner);
        }
        miners[0] ++> BatchRecord(
            message=self.message,
            mercury_g=b.mercury_g,
            to_air_g=e.to_air_g,
            to_tailings_g=e.to_tailings_g,
            risk=e.risk
        );

        report {
            "batch": {
                "ore_kg": b.ore_kg,
                "mercury_g": b.mercury_g,
                "amalgamation": b.amalgamation.name,
                "burning": b.burning.name
            },
            "estimate": {
                "to_air_g": e.to_air_g,
                "to_tailings_g": e.to_tailings_g,
                "risk": e.risk,
                "assumed": e.assumed
            },
            "advice": advise(b, e),
            "if_switched": switch_saving(b),
            "impact": impact_summary(coop)
        };
    }
}

walker:pub get_impact {
    can run with Root entry {
        report impact_summary(get_coop());
    }
}