import from byllm.lib { Model }
import from datetime { datetime }

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
    has air_status: str;
    has tailings_status: str;
}

# ---------------------------------------------------------------
# EVIDENCE LABELS
# ESTIMATED: air release uses a retort or open-burning factor (see README).
# NOT VALIDATED: tailings fractions are placeholders with no source yet.
# MODELLED: what-if savings are scenario results, not measured outcomes.
# ---------------------------------------------------------------
glob STATUS_AIR: str = "ESTIMATED";
glob STATUS_TAILINGS: str = "NOT VALIDATED";
glob STATUS_MODEL: str = "MODELLED";

# ---------------------------------------------------------------
# LOSS FACTORS - ILLUSTRATIVE PLACEHOLDERS.
# Retort capture (90%) is within published ranges (UNEP guide: 5-20% escape).
# The tailings fractions are NOT VALIDATED: no source gives a tailings-versus-air
# split for each method. Calibrate before any real-world use.
# ---------------------------------------------------------------
# Share of the mercury used that ends up in tailings (soil/water).
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
        assumed=assumed,
        air_status=STATUS_AIR,
        tailings_status=STATUS_TAILINGS
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
    has ore_kg: float;
    has mercury_g: float;
    has amalgamation: str;
    has burning: str;
    has to_air_g: float;
    has to_tailings_g: float;
    has risk: str;
    has assumed: bool;
    has when: str;
}

# ---------- Helpers: text to enum, and views for the web page ----------
def to_amalgamation(s: str) -> Amalgamation {
    if s == "WHOLE_ORE" {
        return Amalgamation.WHOLE_ORE;
    }
    if s == "CONCENTRATE" {
        return Amalgamation.CONCENTRATE;
    }
    if s == "MERCURY_FREE" {
        return Amalgamation.MERCURY_FREE;
    }
    return Amalgamation.UNKNOWN;
}

def to_burning(s: str) -> Burning {
    if s == "OPEN_BURNING" {
        return Burning.OPEN_BURNING;
    }
    if s == "RETORT" {
        return Burning.RETORT;
    }
    if s == "NONE" {
        return Burning.NONE;
    }
    return Burning.UNKNOWN;
}

def batch_view(b: Batch) -> dict {
    return {
        "ore_kg": b.ore_kg,
        "mercury_g": b.mercury_g,
        "amalgamation": b.amalgamation.name,
        "burning": b.burning.name
    };
}

def estimate_view(e: Estimate) -> dict {
    return {
        "to_air_g": e.to_air_g,
        "to_tailings_g": e.to_tailings_g,
        "risk": e.risk,
        "assumed": e.assumed,
        "air_status": e.air_status,
        "tailings_status": e.tailings_status
    };
}

# ---------- Agent 4: Impact (adds up the graph) ----------
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
    needs_info = 0;
    miner_rows = [];
    timeline = [];
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
            if r.assumed {
                needs_info += 1;
            }
            timeline.append({
                "when": r.when,
                "miner": m.name,
                "used_g": r.mercury_g,
                "air_g": r.to_air_g,
                "tailings_g": r.to_tailings_g,
                "risk": r.risk
            });
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
        "miners_count": len(miner_rows),
        "batches": batches,
        "high_risk": high,
        "needs_info": needs_info,
        "used_g": int(used * 10 + 0.5) / 10,
        "air_g": int(air * 10 + 0.5) / 10,
        "tailings_g": int(tailings * 10 + 0.5) / 10,
        "avoided_g": int((used - air - tailings) * 10 + 0.5) / 10,
        "air_status": STATUS_AIR,
        "tailings_status": STATUS_TAILINGS,
        "miners": miner_rows,
        "timeline": timeline
    };
}

# ---------- What-if: what would switching method save? (MODELLED) ----------
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
        "saved_g": int(saved * 10 + 0.5) / 10,
        "status": STATUS_MODEL
    };
}

# Step 1 of the new flow: extract and estimate, but do NOT save.
# The miner reviews the extracted values before anything is recorded.
walker:pub preview_batch {
    has message: str;

    can run with Root entry {
        b = extract_batch(self.message);
        e = estimate(b);
        report {
            "batch": batch_view(b),
            "estimate": estimate_view(e),
            "advice": advise(b, e),
            "if_switched": switch_saving(b)
        };
    }
}

# Step 2 of the new flow: save the batch with the values the miner confirmed.
# Rejects an exact repeat (same miner, same report text, same mercury amount).
walker:pub save_batch {
    has miner: str;
    has message: str;
    has ore_kg: float;
    has mercury_g: float;
    has amalgamation: str;
    has burning: str;

    can run with Root entry {
        coop = get_coop();
        b = Batch(
            ore_kg=self.ore_kg,
            mercury_g=self.mercury_g,
            amalgamation=to_amalgamation(self.amalgamation),
            burning=to_burning(self.burning)
        );
        e = estimate(b);

        miners = [x for x in [coop --> [?:Miner]] if x.name == self.miner];
        if not miners {
            miners = coop ++> Miner(name=self.miner);
        }
        miner = miners[0];

        repeats = [r for r in [miner --> [?:BatchRecord]] if r.message == self.message and r.mercury_g == self.mercury_g];
        if repeats {
            report {"saved": False, "reason": "duplicate", "impact": impact_summary(coop)};
        } else {
            miner ++> BatchRecord(
                message=self.message,
                ore_kg=b.ore_kg,
                mercury_g=b.mercury_g,
                amalgamation=b.amalgamation.name,
                burning=b.burning.name,
                to_air_g=e.to_air_g,
                to_tailings_g=e.to_tailings_g,
                risk=e.risk,
                assumed=e.assumed,
                when=datetime.now().strftime("%Y-%m-%d %H:%M")
            );
            report {"saved": True, "reason": "", "impact": impact_summary(coop)};
        }
    }
}

# Kept for compatibility: extract, estimate and save in one step (no review).
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
            ore_kg=b.ore_kg,
            mercury_g=b.mercury_g,
            amalgamation=b.amalgamation.name,
            burning=b.burning.name,
            to_air_g=e.to_air_g,
            to_tailings_g=e.to_tailings_g,
            risk=e.risk,
            assumed=e.assumed,
            when=datetime.now().strftime("%Y-%m-%d %H:%M")
        );

        report {
            "batch": batch_view(b),
            "estimate": estimate_view(e),
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
