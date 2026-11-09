# Zebaki 🌍

**Zebaki** (Swahili for *mercury*) is a prototype multi-agent tool that helps artisanal and small-scale gold miners, and the cooperatives that support them, see how much mercury each batch releases to air and to tailings. Miners describe a batch in Swahili or English, and the agents turn that into an estimate, a risk rating and practical advice.

Built for the Green Shift Hacks hackathon (HackathonForEveryone, Devpost).

## The problem

Artisanal and small-scale gold mining (ASGM) is one of the largest sources of mercury pollution in the world. Miners use mercury to capture gold from ore. Much of it is lost to tailings, soil and water, and much of the rest is released to the air when the amalgam is burned in the open. Most miners have no simple way to know how much mercury they lose per batch, or what a cleaner method would save.

## Who it is for

- **Miners and mining cooperatives**, who want to see their losses and find cheaper, cleaner methods.
- **NGOs, extension officers and programme staff**, who track cooperative-level progress.

## How it works

Zebaki uses four agents, plus a rule-based estimator:

| Step | What it does | Type |
|---|---|---|
| **Intake agent** | Reads a batch report in Swahili or English and extracts ore weight, mercury used, amalgamation method and burning method. Returns `UNKNOWN` when the report doesn't say. | AI (NLP, via Claude) |
| **Estimator** | Applies loss factors to estimate mercury lost to air and to tailings, and assigns a risk rating (HIGH, MEDIUM or LOW). | Rules (no AI guessing) |
| **Advisor agent** | Explains the result to the miner in plain Swahili and suggests one practical step. | AI (NLP, via Claude) |
| **Impact agent** | Walks the cooperative's graph of miners and batches, and totals mercury used, lost and avoided. | Graph walker (Jac) |

The cooperative, its miners and their batches are stored as a graph in Jac.

## Environmental benefit

Zebaki measures impact in **grams of mercury**:

- **Mercury lost to air**: released from open burning, or from amalgam that isn't captured by a retort.
- **Mercury lost to tailings**: left in the soil and water from whole-ore amalgamation.
- **Mercury avoided**: the difference between all mercury used and all mercury lost. It is compared with a worst case in which every gram is lost.

The aim is to show miners, in grams, how much a cleaner method would reduce their losses.

## Limitations

- **The loss factors are prototype assumptions.** The values in `server.jac` (for example 75% tailings loss for whole-ore amalgamation and 90% retort capture) are placeholders. They must be checked against published ASGM guidance before any real use. Sources: [add UNEP / Minamata / Global Mercury Project references here].
- **Estimates, not measurements.** Zebaki does not measure mercury in air, water or soil.
- **AI reads free text.** Messages that are unclear or incomplete may be read incorrectly. Missing details are marked `UNKNOWN` and treated as worst case, and the page says so.
- **Not validated with miners or cooperatives.** Field testing is the next step.

## Tools used

- **Jac** (jaclang) for the agents, graph and web server
- **byLLM** for the AI calls
- **Claude** (Anthropic API) for NLP
- **jac-scale** for serving the web page
- Plain HTML, CSS and JavaScript for the page

## Run it locally

1. Install Python 3.12 or newer.
2. Create and activate a virtual environment:
   ```
   python -m venv venv
   venv\Scripts\activate          # Windows
   source venv/bin/activate       # macOS / Linux
   ```
3. Install the requirements:
   ```
   pip install -r requirements.txt
   ```
4. Set your API key. **Never commit it to the repository.**
   ```
   set ANTHROPIC_API_KEY=your-key-here          # Windows Command Prompt
   $env:ANTHROPIC_API_KEY="your-key-here"       # Windows PowerShell
   export ANTHROPIC_API_KEY=your-key-here       # macOS / Linux
   ```
5. Run the command-line demo (four sample batches):
   ```
   jac run zebaki.jac
   ```
6. Run the web version and open the page:
   ```
   jac start server.jac --no_client
   ```
   Then open `http://localhost:8000/static/index.html` (use the port shown in the terminal if it differs).

## Project files

- `zebaki.jac`: command-line demo that runs the agents and the cooperative graph
- `server.jac`: the web API (agents, estimator, graph and endpoints)
- `assets/index.html`: the web page
- `requirements.txt`: pinned versions tested with this project
- `jac.toml`: project configuration

## Deployment

Hosted on Render with the start command:
```
jac start server.jac --port $PORT --no_client
```
Set `ANTHROPIC_API_KEY` in Render's environment settings. The free tier sleeps when idle, so the first visit may take about a minute.

## Licence and data

Built during the hackathon. No real miner data is included. All sample batches are invented for demonstration.
