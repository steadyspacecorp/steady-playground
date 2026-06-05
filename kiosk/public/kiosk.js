// Steady Kiosk -- subscribe to /events (SSE) and render shapes + bars.
//
// Elements are keyed by id and updated in place so CSS transitions animate
// status color and bar width changes instead of redrawing from scratch.

const peopleEls = new Map();
const goalEls = new Map();

// Steady's canonical mood -> emoji mapping (CheckIn#mood).
const MOOD_EMOJI = {
  calm: "😌",
  happy: "🙂",
  excited: "🤗",
  celebratory: "🤩",
  joyful: "😂",
  confident: "😎",
  focused: "🧐",
  goofy: "🤪",
  nerdy: "🤓",
  thoughtful: "🤔",
  meh: "😐",
  confused: "😕",
  flustered: "😳",
  surprised: "😲",
  tired: "😴",
  disappointed: "🙁",
  worried: "😟",
  annoyed: "🙄",
  stressed: "🤯",
  angry: "😠",
  sick: "🤒",
};

const live = document.getElementById("live");
const message = document.getElementById("message");
const teams = document.getElementById("teams");
const updatedAt = document.getElementById("updated-at");

// Double-click anywhere to toggle fullscreen -- handy on wall displays
// where launching the browser in kiosk mode isn't an option.
document.addEventListener("dblclick", () => {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen();
});

const source = new EventSource("/events");

source.onmessage = (event) => {
  const data = JSON.parse(event.data);
  renderPeople(data.people || []);
  renderGoals(data.goals || []);

  message.textContent = data.error || "";
  live.classList.toggle("error", Boolean(data.error));
  teams.textContent = data.error ? "" : (data.teams || []).join(", ");
  if (data.updated_at) {
    const time = new Date(data.updated_at).toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
    });
    updatedAt.textContent = `Updated ${time}`;
  }
};

source.onerror = () => {
  message.textContent = "Reconnecting…";
  live.classList.add("error");
};

source.onopen = () => {
  live.classList.remove("error");
};

// Pick the column count that maximizes symbol size for n shapes in the
// grid's current width and height, and hand the result to the CSS.
function layoutPeople() {
  const grid = document.getElementById("people");
  const n = peopleEls.size;
  if (!n) return;

  const gap = parseFloat(getComputedStyle(grid).gap) || 16;
  const { clientWidth: w, clientHeight: h } = grid;
  let best = { cols: 1, cell: 0 };
  for (let cols = 1; cols <= n; cols++) {
    const rows = Math.ceil(n / cols);
    const cell = Math.min((w - gap * (cols - 1)) / cols, (h - gap * (rows - 1)) / rows);
    if (cell > best.cell) best = { cols, cell };
  }
  grid.style.setProperty("--cols", best.cols);
  grid.style.setProperty("--cell", `${Math.floor(best.cell)}px`);
}

new ResizeObserver(layoutPeople).observe(document.getElementById("people"));

function renderPeople(people) {
  const grid = document.getElementById("people");
  sync(grid, peopleEls, people, (person, el) => {
    if (!el) {
      el = document.createElement("div");
      el.classList.add("enter");
      el.innerHTML = '<span class="face"></span><span class="mood"></span>';
    }
    el.className = `person ${person.kind} status-${person.status}` + (el.classList.contains("enter") ? " enter" : "");
    el.title = person.name + (person.mood ? ` — ${person.mood}` : "");
    el.querySelector(".face").textContent = person.initials;
    el.querySelector(".mood").textContent =
      person.kind === "agent" ? "🤖" : MOOD_EMOJI[person.mood] || "";
    return el;
  });
  emptyState(grid, people.length, "No team members");
  layoutPeople();
}

function renderGoals(goals) {
  const stack = document.getElementById("goals");
  sync(stack, goalEls, goals, (goal, el) => {
    if (!el) {
      el = document.createElement("div");
      el.classList.add("enter");
      el.innerHTML =
        '<div class="fill"></div><div class="label"><span class="title"></span><span class="pct"></span></div>';
    }
    el.className = `goal goal-${goal.status}` + (el.classList.contains("enter") ? " enter" : "");
    el.style.marginLeft = `${(goal.depth || 0) * 2}rem`;
    el.title = `${goal.title} — ${goal.progress}%`;
    el.querySelector(".fill").style.width = `${goal.progress}%`;
    el.querySelector(".title").textContent = goal.title;
    el.querySelector(".pct").textContent = `${goal.progress}%`;
    return el;
  });
  emptyState(stack, goals.length, "No top-level goals");
}

// Reconcile a container's children against `items`: create or update via
// `build`, append in order (appendChild moves existing nodes), drop stale.
function sync(container, els, items, build) {
  const seen = new Set();
  for (const item of items) {
    const el = build(item, els.get(item.id));
    els.set(item.id, el);
    seen.add(item.id);
    container.appendChild(el);
    requestAnimationFrame(() => el.classList.remove("enter"));
  }
  for (const [id, el] of els) {
    if (!seen.has(id)) {
      el.remove();
      els.delete(id);
    }
  }
}

function emptyState(container, count, text) {
  let note = container.querySelector(".empty");
  if (count) {
    note?.remove();
  } else if (!note) {
    note = document.createElement("p");
    note.className = "empty";
    note.textContent = text;
    container.appendChild(note);
  }
}
