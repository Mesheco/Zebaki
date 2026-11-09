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
# LOSS FACTORS - PROTOTYPE ASSUMPTIONS.
# Check these against UNEP / Minamata Convention ASGM guidance
# before you submit, and cite the source in your Devpost write-up.
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
    assumed = (b.amalgamation == Amalgamation.UNKNOWN) or (b.burning == Burning.UNKNOWN);

    to_tailings: float = b.mercury_g * TAILINGS_SHARE[b.amalgamation];
    in_amalgam: float = b.mercury_g - to_tailings;

    # Open burning or unknown: assume all mercury in the amalgam goes to air.
    to_air: float = in_amalgam;
    if b.burning == Burning.RETORT {
        to_air = in_amalgam * (1 - RETORT_CAPTURE);
    } elif b.burning == Burning.NONE {
        to_air = 0.0;
    }

    risk = "LOW";
    if (b.amalgamation == Amalgamation.WHOLE_ORE) or (b.burning == Burning.OPEN_BURNING) {
        risk = "HIGH";
    } elif assumed {
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

# Adds one batch report to a miner (creates the miner if new)
def log_batch(coop: Cooperative, miner_name: str, message: str) -> BatchRecord {
    b = extract_batch(message);
    e = estimate(b);

    m: Miner | None = None;
    for x in [coop --> [?:Miner]] {
        if x.name == miner_name {
            m = x;
        }
    }
    if m is None {
        m = (coop ++> Miner(name=miner_name))[0];
    }

    rec = (m ++> BatchRecord(
        message=message,
        mercury_g=b.mercury_g,
        to_air_g=e.to_air_g,
        to_tailings_g=e.to_tailings_g,
        risk=e.risk
    ))[0];
    return rec;
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

with entry {
    coop = (root ++> Cooperative(name="Ushirika wa Wachimbaji - Demo"))[0];

    reports = [
        ["Juma", "Nimetumia gramu 50 za zebaki kwa kilo 200 za mchanga mzima"],
        ["Amina", "Used 30g mercury on concentrate from 500kg ore, then burned it in a retort"],
        ["Amina", "Leo tumetumia zebaki gramu 20 kwa kilo 100 za concentrate, tumetumia retort"],
        ["Juma", "Tulichoma amalgam wazi bila retort, zebaki gramu 40 kwa kilo 150 za mchanga mzima"]
    ];

    for r in reports {
        rec = log_batch(coop, r[0], r[1]);
        print(r[0] + ": " + rec.risk + " | air " + str(rec.to_air_g) + " g | tailings " + str(rec.to_tailings_g) + " g");
    }

    w = coop spawn ImpactReport();
    lost = w.air_g + w.tailings_g;
    avoided = w.used_g - lost;

    print("========== " + coop.name + " ==========");
    print("Batches: " + str(w.batches) + " (high risk: " + str(w.high_risk) + ")");
    print("Mercury used:      " + str(w.used_g) + " g");
    print("Lost to air:       " + str(w.air_g) + " g");
    print("Lost to tailings:  " + str(w.tailings_g) + " g");
    print("Mercury avoided:   " + str(avoided) + " g (vs all mercury lost)");
}
