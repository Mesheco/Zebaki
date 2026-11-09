# Zebaki 🌍

**Zebaki** (Swahili for *mercury*) is a prototype multi-agent tool that helps artisanal and small-scale gold miners (ASGM), and the cooperatives that support them, see how much mercury each batch releases to air and to tailings. A miner describes a batch in Swahili or English. The agents turn that into an estimate, a risk rating, practical advice and a "what if" saving, and add the batch to the cooperative's running total.

Built for the Green Shift Hacks hackathon (HackathonForEveryone, Devpost).

## The problem

ASGM is one of the largest sources of mercury pollution in the world. Miners use mercury to capture gold from ore. Much of it is lost to tailings, soil and water, and much of the rest is released to the air when the amalgam is burned in the open. Most miners have no simple way to know how much mercury they lose per batch, or what a cleaner method would save.

## Who it is for

- **Miners and mining cooperatives**, who want to see their losses and find cheaper, cleaner methods.
- **NGOs and programme staff**, who track cooperative-level progress.

## How the agents work together

Every batch follows the same path through the system:

```mermaid
flowchart TD
    M["Miner's message<br/>(Swahili or English)"] --> I
    I["1. Intake agent (AI, NLP)<br/>Extracts ore, mercury,<br/>amalgamation and burning method"] --> E
    E["2. Estimator (rules)<br/>Mercury to air and tailings,<br/>risk rating"] --> A
    E --> W
    A["3a. Advisor agent (AI, NLP)<br/>Advice in Swahili"] --> R
    W["3b. What-if calculator (rules)<br/>Grams saved by switching"] --> R
    E --> G
    G["4. Cooperative graph (Jac)<br/>Cooperative → Miner → BatchRecord"] --> P
    P["5. Impact (walks the graph)<br/>Totals: