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

"""Extract mining batch details from a miner's message in Swahili or English.
If the message does not mention how the amalgam was burned, use UNKNOWN."""
def extract_batch(message: str) -> Batch by llm(temperature=None);

with entry {
    messages = [
        "Nimetumia gramu 50 za zebaki kwa kilo 200 za mchanga mzima",
        "Used 30g mercury on concentrate from 500kg ore, then burned it in a retort",
        "Leo tumetumia zebaki gramu 20 kwa kilo 100, tumetumia retort",
        "Tulichoma amalgam wazi bila retort, zebaki gramu 40 kwa kilo 150 za mchanga mzima"
    ];

    for msg in messages {
        print("Message: " + msg);
        print(extract_batch(msg));
        print("---");
    }
}