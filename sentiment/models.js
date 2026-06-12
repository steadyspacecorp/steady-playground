// The NLP half of Steady Sentiment -- two small transformer models running
// on-CPU via Transformers.js. No LLMs anywhere:
//
//   score: distilbert-base-uncased-finetuned-sst-2-english  (binary pos/neg)
//   color: roberta-base-go_emotions                         (28 emotions,
//          folded into the 7 Ekman buckets the aurora paints)
//
// Check-in markdown is stripped and split into sentence-ish fragments, each
// fragment is scored by both models, and the results roll up into one team
// snapshot: a headline score in -1..1, an "energy" (how much the fragments
// disagree with each other), and a blended emotion mix that becomes the
// aurora's palette.

import { pipeline, env as hf } from "@huggingface/transformers";

export const SENTIMENT_MODEL = "Xenova/distilbert-base-uncased-finetuned-sst-2-english";
export const EMOTION_MODEL = "SamLowe/roberta-base-go_emotions-onnx";

// GoEmotions returns 28 fine-grained labels; the aurora paints 7. Fold the
// fine labels into the Ekman buckets aurora.js knows (joy, surprise, neutral,
// sadness, fear, anger, disgust) so the palette and shader stay untouched.
const EKMAN = {
  admiration: "joy", amusement: "joy", approval: "joy", caring: "joy",
  desire: "joy", excitement: "joy", gratitude: "joy", joy: "joy",
  love: "joy", optimism: "joy", pride: "joy", relief: "joy",
  surprise: "surprise", curiosity: "surprise", realization: "surprise", confusion: "surprise",
  neutral: "neutral",
  sadness: "sadness", disappointment: "sadness", grief: "sadness",
  remorse: "sadness", embarrassment: "sadness",
  fear: "fear", nervousness: "fear",
  anger: "anger", annoyance: "anger", disapproval: "anger",
  disgust: "disgust",
};

// Collapse one fragment's 28 GoEmotions scores into the 7 Ekman buckets.
function toEkman(scores) {
  const mix = {};
  for (const { label, score } of scores) {
    const bucket = EKMAN[label] || "neutral";
    mix[bucket] = (mix[bucket] || 0) + score;
  }
  return mix;
}

// Cache model weights next to the app (tmp/ is gitignored). Docker builds
// override this so the image ships with the weights baked in.
hf.cacheDir = process.env.MODELS_DIR || "./tmp/models";

let loaded = null;

export function loadModels() {
  loaded ??= Promise.all([
    pipeline("text-classification", SENTIMENT_MODEL, { dtype: "q8" }),
    pipeline("text-classification", EMOTION_MODEL, { dtype: "q8" }),
  ]).then(([sentiment, emotion]) => ({ sentiment, emotion }));
  return loaded;
}

// --- fragmenting ----------------------------------------------------------

// Check-in answers arrive as Markdown: bullet lists of links, code, and
// prose. Strip the markup, drop URLs and code (no mood in a commit hash),
// and split what's left into sentence-ish fragments the models can score.
const MAX_FRAGMENT_CHARS = 400;
const MAX_FRAGMENTS_PER_FIELD = 20;

export function fragments(markdown) {
  if (!markdown) return [];
  const text = markdown
    .replace(/```[\s\S]*?```/g, " ") // fenced code blocks
    .replace(/`([^`]+)`/g, "$1") // inline code -> bare text
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ") // images
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1") // links -> link text
    .replace(/https?:\/\/\S+/g, " ") // bare URLs
    .replace(/[*_~#>]+/g, " "); // emphasis, headings, quotes
  return text
    .split("\n")
    .map((line) => line.replace(/^\s*(?:[-+•]|\d+[.)])\s*/, "").trim())
    .flatMap((line) => line.split(/(?<=[.!?])\s+/))
    .map((s) => s.replace(/\s+/g, " ").trim().slice(0, MAX_FRAGMENT_CHARS))
    .filter((s) => s.split(" ").length >= 3 && /[a-zA-Z]{3}/.test(s))
    .slice(0, MAX_FRAGMENTS_PER_FIELD);
}

// --- scoring --------------------------------------------------------------

// Blocker text carries more signal about how the day actually feels than a
// list of merged PRs, so it counts double. A blocked check-in also takes a
// flat penalty: being stuck colors the whole day even when the prose is
// upbeat ("just waiting on DNS!").
const FIELD_WEIGHTS = { previous: 1, intentions: 1, blockers: 2 };
const BLOCKED_PENALTY = 0.25;
const BATCH_SIZE = 16;

async function classifyAll(model, texts, options) {
  const results = [];
  for (let i = 0; i < texts.length; i += BATCH_SIZE) {
    const batch = texts.slice(i, i + BATCH_SIZE);
    let output = await model(batch, options);
    // Array in -> array out, but normalize the single-item shapes the
    // pipeline sometimes unwraps: {label,score}, or with top_k null, a
    // bare array of label scores instead of an array of arrays.
    if (!Array.isArray(output)) output = [output];
    if (options?.top_k === null && batch.length === 1 && !Array.isArray(output[0])) output = [output];
    results.push(...output);
  }
  return results;
}

const mean = (values) => values.reduce((sum, v) => sum + v, 0) / values.length;

function weightedMean(items, value) {
  let total = 0;
  let weights = 0;
  for (const item of items) {
    total += value(item) * item.weight;
    weights += item.weight;
  }
  return weights ? total / weights : 0;
}

// Blend emotion distributions: weighted mean per label across fragments.
function blendEmotions(frags) {
  const mix = {};
  let weights = 0;
  for (const f of frags) {
    for (const [label, score] of Object.entries(f.emotions)) {
      mix[label] = (mix[label] || 0) + score * f.weight;
    }
    weights += f.weight;
  }
  for (const label of Object.keys(mix)) mix[label] = Number((mix[label] / weights).toFixed(3));
  return mix;
}

const topEmotion = (mix) =>
  Object.entries(mix).sort((a, b) => b[1] - a[1])[0]?.[0] || "neutral";

export function vibe(score) {
  if (score >= 0.45) return "radiant";
  if (score >= 0.15) return "bright";
  if (score >= -0.15) return "steady";
  if (score >= -0.45) return "strained";
  return "stormy";
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

// Score one day of check-ins. Returns everything the page needs to drive
// the aurora and explain itself in the footer.
export async function scoreCheckIns(checkIns) {
  const frags = [];
  checkIns.forEach((checkIn, index) => {
    for (const [field, weight] of Object.entries(FIELD_WEIGHTS)) {
      for (const text of fragments(checkIn[field])) {
        frags.push({ index, field, text, weight });
      }
    }
  });

  if (!frags.length) {
    return {
      score: 0,
      label: "quiet",
      energy: 0,
      emotions: { neutral: 1 },
      dominant_emotion: "neutral",
      check_in_count: checkIns.length,
      fragment_count: 0,
      blocked_count: 0,
      people: [],
      highlights: {},
      summary: "Nothing to read yet — no scoreable text in today's check-ins.",
    };
  }

  const { sentiment, emotion } = await loadModels();
  const texts = frags.map((f) => f.text);
  const [sents, emos] = await Promise.all([
    classifyAll(sentiment, texts),
    classifyAll(emotion, texts, { top_k: null }),
  ]);

  frags.forEach((f, i) => {
    f.score = sents[i].label === "POSITIVE" ? sents[i].score : -sents[i].score;
    f.emotions = toEkman(emos[i]);
  });

  const people = checkIns
    .map((checkIn, index) => {
      const own = frags.filter((f) => f.index === index);
      if (!own.length) return null;
      const raw = weightedMean(own, (f) => f.score);
      const score = clamp(checkIn.blocked ? raw - BLOCKED_PENALTY : raw, -1, 1);
      return {
        id: checkIn.id,
        name: checkIn.person?.name || "Someone",
        score: Number(score.toFixed(2)),
        blocked: Boolean(checkIn.blocked),
        mood: checkIn.mood || null,
        dominant_emotion: topEmotion(blendEmotions(own)),
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.name.localeCompare(b.name));

  const score = Number(mean(people.map((p) => p.score)).toFixed(2));
  const fragScores = frags.map((f) => f.score);
  const energy = Number(clamp(Math.sqrt(mean(fragScores.map((s) => (s - mean(fragScores)) ** 2))), 0, 1).toFixed(2));
  const emotions = blendEmotions(frags);
  const blockedCount = people.filter((p) => p.blocked).length;

  const brightest = frags.reduce((a, b) => (b.score > a.score ? b : a));
  const heaviest = frags.reduce((a, b) => (b.score < a.score ? b : a));
  const quote = (f) => ({
    text: f.text.length > 160 ? `${f.text.slice(0, 157)}…` : f.text,
    person: checkIns[f.index].person?.name || "Someone",
    field: f.field,
    score: Number(f.score.toFixed(2)),
  });

  return {
    score,
    label: vibe(score),
    energy,
    emotions,
    dominant_emotion: topEmotion(emotions),
    check_in_count: people.length,
    fragment_count: frags.length,
    blocked_count: blockedCount,
    people,
    highlights: {
      brightest: quote(brightest),
      ...(heaviest.score < 0 && { heaviest: quote(heaviest) }),
    },
    summary: summarize({ score, energy, emotions, people, frags, blockedCount }),
  };
}

// The "why" line under the score. Plain facts, composed from the rollup.
function summarize({ score, energy, emotions, people, frags, blockedCount }) {
  const sign = score > 0 ? "+" : "";
  const lead = topEmotion(emotions);
  const parts = [
    `${frags.length} fragments from ${people.length} check-in${people.length === 1 ? "" : "s"} average ${sign}${score} (${vibe(score)})`,
    `${lead} leads the emotion mix at ${Math.round((emotions[lead] || 0) * 100)}%`,
  ];
  if (energy >= 0.55) parts.push("the fragments disagree a lot, so the field runs turbulent");
  if (blockedCount) parts.push(`${blockedCount} blocked check-in${blockedCount === 1 ? "" : "s"} pulse${blockedCount === 1 ? "s" : ""} red`);
  return parts.join(" · ") + ".";
}
