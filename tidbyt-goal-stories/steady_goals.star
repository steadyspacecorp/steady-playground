"""
Steady Goal Stories — a Tidbyt app.

Shows the top-level Steady goals for the token's "my teams" view as a
vertical stack of horizontal progress bars:

  red     off track
  orange  at risk
  blue    on track
  green   complete (progress == 100)
  gray    no update yet

Bar width = the goal's latest `progress` percent. Color = the goal's latest
`confidence_description`. Data comes from the Steady v2 REST API
(https://service.steady.space/api/v2), authenticated with a personal access
token (PAT).
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

API_BASE = "https://service.steady.space/api/v2"

# Display geometry (Tidbyt is 64x32).
WIDTH = 64
HEIGHT = 32

# Bar colors, keyed by confidence_description plus a synthetic "Complete".
COLOR_OFF_TRACK = "#FF5C7D"  # red    — confidence 30
COLOR_AT_RISK = "#FFB459"    # orange — confidence 60
COLOR_ON_TRACK = "#7C7CFF"   # blue   — confidence 90
COLOR_COMPLETE = "#5BCFC9"   # green  — progress 100
COLOR_NO_UPDATE = "#3A3F4A"  # neutral — no update yet
COLOR_TRACK = "#1F2228"      # bar background
COLOR_MESSAGE = "#A6AEC0"

# How long to trust each response. Goals & their updates change daily, not
# minute-by-minute, so a longer TTL is fine and keeps the API call count down.
GOALS_TTL = 300
UPDATES_TTL = 300

def main(config):
    pat = config.str("pat", "").strip()
    if not pat:
        return message("Add token in settings")

    headers = {
        "Authorization": "Bearer " + pat,
        "Accept": "application/json",
    }

    # Match the UI's "My teams" view: only goals involving teams the PAT's
    # person is on. /me returns the person with their teams attached.
    me_resp = http.get(API_BASE + "/me", headers = headers, ttl_seconds = GOALS_TTL)
    if me_resp.status_code != 200:
        return message("Me error %d" % me_resp.status_code)
    team_ids = [t["id"] for t in me_resp.json().get("teams", [])]
    if not team_ids:
        return message("No teams")

    team_query = "&".join(["team_ids%5B%5D=" + tid for tid in team_ids])
    goals_resp = http.get(
        "{}/goals?per_page=50&{}".format(API_BASE, team_query),
        headers = headers,
        ttl_seconds = GOALS_TTL,
    )
    if goals_resp.status_code != 200:
        return message("Goals error %d" % goals_resp.status_code)

    # Top-level goals only — these are the rollups; contributing goals feed
    # into them and would just duplicate signal at this resolution.
    top_level = [g for g in goals_resp.json() if g.get("parent") == None]
    if not top_level:
        return message("No top-level goals")

    # Match the web UI ordering (`Goal.for_index`): end_date ASC, title ASC,
    # with missing end dates sorted to the end.
    top_level = sorted(
        top_level,
        key = lambda g: (g.get("end_date") or "9999-12-31", (g.get("title") or "").lower()),
    )

    height, gap = bar_dims(len(top_level))
    rows = []
    for goal in top_level:
        update = latest_update(headers, goal["id"])
        rows.append(bar_row(update, height, gap))

    return render.Root(
        max_age = UPDATES_TTL,
        child = stack(rows),
    )

def latest_update(headers, goal_id):
    """Return the most recent GoalUpdate for a goal, or None if there are none."""
    url = "{}/goals/{}/goal-updates?per_page=1".format(API_BASE, goal_id)
    resp = http.get(url, headers = headers, ttl_seconds = UPDATES_TTL)
    if resp.status_code != 200:
        return None
    updates = resp.json()
    if not updates:
        return None
    return updates[0]

def status_of(update):
    """Map an update to (color, progress) for rendering. Progress=100 wins
    over confidence so completed goals always read green."""
    if update == None:
        return COLOR_NO_UPDATE, 0
    progress = update.get("progress", 0) or 0
    if progress >= 100:
        return COLOR_COMPLETE, 100
    desc = (update.get("confidence_description") or "").lower()
    if desc == "off track":
        return COLOR_OFF_TRACK, progress
    if desc == "at risk":
        return COLOR_AT_RISK, progress
    if desc == "on track":
        return COLOR_ON_TRACK, progress
    return COLOR_NO_UPDATE, progress

# --- layout -----------------------------------------------------------------

def stack(rows):
    """Vertically center a column of bars in the 64x32 display."""
    return render.Box(
        width = WIDTH,
        height = HEIGHT,
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            children = rows,
        ),
    )

def bar_row(update, height, gap):
    """Build one row: a colored bar over a dim track, with bottom padding."""
    color, progress = status_of(update)
    fill_w = int(progress * WIDTH // 100)
    if progress > 0 and fill_w == 0:
        fill_w = 1

    track = render.Box(width = WIDTH, height = height, color = COLOR_TRACK)
    if fill_w == 0:
        bar = track
    else:
        bar = render.Stack(children = [
            track,
            render.Box(width = fill_w, height = height, color = color),
        ])
    return render.Padding(pad = (0, 0, 0, gap), child = bar)

def bar_dims(n):
    """Pick a bar height + gap that fits n bars in HEIGHT."""
    # (height, gap) tuned to keep bars readable and the stack centered.
    if n <= 1:
        return 24, 0
    if n == 2:
        return 14, 2
    if n == 3:
        return 8, 2
    if n == 4:
        return 6, 2
    if n == 5:
        return 5, 1
    if n == 6:
        return 4, 1
    if n == 7:
        return 3, 1
    if n == 8:
        return 3, 1
    if n <= 10:
        return 2, 1
    return 2, 0

# --- messages & schema ------------------------------------------------------

def message(text):
    return render.Root(
        child = render.Box(
            width = WIDTH,
            height = HEIGHT,
            child = render.WrappedText(
                content = text,
                font = "tom-thumb",
                color = COLOR_MESSAGE,
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
        ],
    )
