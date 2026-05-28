"""
Steady Check-ins — a Tidbyt app.

Shows today's check-in status for a Steady team as a grid of colored symbols:

  yellow  no check-in yet
  blue    checked in
  green   checked in and intentions met
  red     blocked

  circle  person      square  agent

Data comes from the Steady v2 REST API (https://service.steady.space/api/v2),
authenticated with a personal access token (PAT).
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

API_BASE = "https://service.steady.space/api/v2"

# Display geometry (Tidbyt is 64x32).
WIDTH = 64
HEIGHT = 32

# Status colors, brightest-first to read well on the LED matrix.
COLOR_PENDING = "#1F2228"  # gray  — no check-in yet
COLOR_CHECKED = "#514CFA"  # blue    — checked in
COLOR_DONE = "#6AC1C2"     # green   — intentions met
COLOR_BLOCKED = "#FF7792"  # red     — blocked
COLOR_DIM = "#A6AEC0"      # neutral — messages

# Cache lifetimes. Team membership changes rarely; check-ins change all day.
TEAM_TTL = 300
CHECKINS_TTL = 60

DEFAULT_TZ = "America/New_York"

def main(config):
    pat = config.str("pat", "").strip()
    if not pat:
        return message("Add token in settings")

    headers = {
        "Authorization": "Bearer " + pat,
        "Accept": "application/json",
    }

    team_id = config.str("team_id", "").strip()
    team_name = config.str("team_name", "").strip()
    if not team_id and team_name:
        team_id = lookup_team_by_name(headers, team_name)
        if not team_id:
            return message("No team named " + team_name)
    if not team_id:
        return message("Pick a team in settings")

    team_resp = http.get(
        API_BASE + "/teams/" + team_id,
        headers = headers,
        ttl_seconds = TEAM_TTL,
    )
    if team_resp.status_code != 200:
        return message("Team error %d" % team_resp.status_code)

    people = team_resp.json().get("people", [])
    if not people:
        return message("No team members")

    today = today_in_tz(config)
    by_person = check_ins_by_person(headers, team_id, today)

    # Stable ordering so the grid doesn't shuffle between renders.
    people = sorted(people, key = lambda p: p["name"].lower())

    symbols = []
    for person in people:
        check_in = by_person.get(person["id"])
        symbols.append((shape_for(person), status_color(check_in)))

    return render.Root(
        max_age = CHECKINS_TTL,
        child = grid(symbols),
    )

def lookup_team_by_name(headers, name):
    """Find a team's UUID by name (case-insensitive). Used for CLI rendering;
    the settings UI sets `team_id` directly via the dropdown."""
    resp = http.get(API_BASE + "/teams?per_page=50", headers = headers, ttl_seconds = TEAM_TTL)
    if resp.status_code != 200:
        return None
    for team in resp.json():
        if team["name"].strip().lower() == name.lower():
            return team["id"]
    return None

def check_ins_by_person(headers, team_id, today):
    """Return {person_id: check_in} for the team's check-ins on `today`."""
    url = "{}/check-ins?since={}&until={}&team_ids%5B%5D={}&per_page=50".format(
        API_BASE,
        today,
        today,
        team_id,
    )
    resp = http.get(url, headers = headers, ttl_seconds = CHECKINS_TTL)
    if resp.status_code != 200:
        return {}

    by_person = {}
    for check_in in resp.json():
        by_person[check_in["person"]["id"]] = check_in
    return by_person

def status_color(check_in):
    if check_in == None:
        return COLOR_PENDING
    if check_in.get("blocked"):
        return COLOR_BLOCKED
    if check_in.get("previous_completed") == True:
        return COLOR_DONE
    return COLOR_CHECKED

def shape_for(person):
    """Circle for people, square for agents.

    The v2 API does not yet expose a person-vs-agent type, so everyone renders
    as a circle for now. When the API gains that field, switch on it here.
    """
    return "circle"

# --- layout -----------------------------------------------------------------

def grid(symbols):
    """Lay out (shape, color) symbols as a centered grid sized to fit."""
    n = len(symbols)
    diameter, gap, cols = grid_dims(n)
    cols = min(cols, n)

    # Fill rows left-to-right; a short last row stays left-aligned under the
    # first column. The whole block is centered in the display.
    rows = []
    for start in range(0, n, cols):
        row = symbols[start:start + cols]
        rows.append(render.Row(
            main_align = "start",
            cross_align = "center",
            children = [cell(shape, color, diameter, gap) for (shape, color) in row],
        ))

    return render.Box(
        width = WIDTH,
        height = HEIGHT,
        child = render.Column(
            main_align = "center",
            cross_align = "start",
            children = rows,
        ),
    )

def cell(shape, color, diameter, gap):
    """Build one symbol at `diameter`, wrapped in a uniform spacing box."""
    if shape == "square":
        sized = render.Box(width = diameter, height = diameter, color = color)
    else:
        sized = render.Circle(color = color, diameter = diameter)
    return render.Box(width = diameter + gap, height = diameter + gap, child = sized)

def grid_dims(n):
    """Pick the largest symbol size whose grid fits n cells in WIDTH x HEIGHT.

    Each cell is (diameter + gap) square, so the block is cols * (diameter + gap)
    wide; that must stay within WIDTH (likewise rows within HEIGHT).
    """
    for diameter in [14, 12, 10, 9, 8, 7, 6, 5, 4, 3]:
        gap = 2 if diameter >= 8 else 1
        cell = diameter + gap
        cols = WIDTH // cell
        grid_rows = HEIGHT // cell
        if cols > 0 and grid_rows > 0 and cols * grid_rows >= n:
            return diameter, gap, cols
    return 3, 1, WIDTH // 4

# --- time -------------------------------------------------------------------

def today_in_tz(config):
    tz = config.get("$tz", DEFAULT_TZ)
    return time.now().in_location(tz).format("2006-01-02")

# --- messages & schema ------------------------------------------------------

def message(text):
    return render.Root(
        child = render.Box(
            width = WIDTH,
            height = HEIGHT,
            child = render.WrappedText(
                content = text,
                font = "tom-thumb",
                color = COLOR_PENDING,
                align = "center",
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "pat",
                name = "Personal access token",
                desc = "Steady PAT (starts with steady_pat_), created in Steady settings.",
                icon = "key",
            ),
            schema.Generated(
                id = "team_picker",
                source = "pat",
                handler = team_options,
            ),
        ],
    )

def team_options(pat):
    """Populate a team dropdown (by name) from the token's visible teams."""
    pat = pat.strip()
    if not pat:
        return []

    resp = http.get(
        API_BASE + "/teams?per_page=50",
        headers = {"Authorization": "Bearer " + pat, "Accept": "application/json"},
        ttl_seconds = TEAM_TTL,
    )
    if resp.status_code != 200:
        return []

    teams = sorted(resp.json(), key = lambda t: t["name"].lower())
    options = [schema.Option(display = t["name"], value = t["id"]) for t in teams]
    if not options:
        return []

    return [
        schema.Dropdown(
            id = "team_id",
            name = "Team",
            desc = "Team whose check-ins to display.",
            icon = "userGroup",
            default = options[0].value,
            options = options,
        ),
    ]
