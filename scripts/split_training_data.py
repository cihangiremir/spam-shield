"""Gives every training message without a `split` field one: train (80%), validation (10%) or test (10%).

Near-duplicates (same label, mostly the same words once numbers and links are left out) always share a split,
so a test message never has a slightly changed copy in training. Messages that already have a split keep it,
and a new message joins the split of a near-duplicate it has, so adding data doesn't reshuffle the test set.

Run from the repository root:  python3 scripts/split_training_data.py
"""
import hashlib
import json
import re
import sys
from pathlib import Path

FILES = [Path("FilterCore/TrainingData/messages.json"), Path("FilterCore/TrainingData/synthetic.json")]
FOLD = str.maketrans({"ı": "i", "ş": "s", "ğ": "g", "ü": "u", "ö": "o", "ç": "c", "â": "a", "î": "i", "û": "u"})
LINK = re.compile(r"(https?://|www\.)\S+|\S+\.(com|net|org|tr|xyz|info|top|site|link|click|ly|la|gl|io|co)\b\S*")
SIMILARITY = 0.5


def words(text):
    text = LINK.sub(" ", text.replace("I", "ı").replace("İ", "i").lower().translate(FOLD))
    return {w for w in re.findall(r"[a-z]+", text) if len(w) >= 2}


def split_for(text):
    bucket = int(hashlib.sha256(" ".join(text.split()).encode()).hexdigest(), 16) % 10
    return "test" if bucket == 0 else "validation" if bucket == 1 else "train"


def write(path, messages):
    lines = ",\n".join("  " + json.dumps(m, ensure_ascii=False) for m in messages)
    path.write_text("[\n" + lines + "\n]\n", encoding="utf-8")


def main():
    files = {path: json.loads(path.read_text(encoding="utf-8")) for path in FILES if path.exists()}
    messages = [m for ms in files.values() for m in ms]
    word_sets = [words(m["text"]) for m in messages]
    frequency = {}
    for ws in word_sets:
        for w in ws:
            frequency[w] = frequency.get(w, 0) + 1

    # Candidates share one of a message's rarest words; comparing every pair would be slow.
    index = {}
    def near_duplicates(i):
        found = set()
        for w in sorted(word_sets[i], key=frequency.get)[:4]:
            for j in index.get(w, ()):
                union = len(word_sets[i] | word_sets[j])
                if messages[j]["label"] == messages[i]["label"] and union \
                        and len(word_sets[i] & word_sets[j]) / union >= SIMILARITY:
                    found.add(j)
        return found

    # Messages with a split go first, so new ones can join their near-duplicates' split.
    order = sorted(range(len(messages)), key=lambda i: "split" not in messages[i])
    added = 0
    for i in order:
        if "split" not in messages[i]:
            splits = [messages[j]["split"] for j in near_duplicates(i)]
            messages[i]["split"] = min(splits) if splits else split_for(messages[i]["text"])
            added += 1
        for w in sorted(word_sets[i], key=frequency.get)[:4]:
            index.setdefault(w, []).append(i)

    for path, ms in files.items():
        write(path, [{**{k: v for k, v in m.items() if k != "split"}, "split": m["split"]} for m in ms])
    print(f"{added} messages got a split", file=sys.stderr)


if __name__ == "__main__":
    main()
