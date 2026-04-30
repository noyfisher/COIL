"""
Shared fuzzy matching module for exercise image resolution.

Ports the 7-layer matching algorithm from ExerciseImageService.swift to Python.
Used by stockpile_exercise_images.py, process_missing_images.py, and test scripts.
"""

import json
import re
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional


class MatchType(Enum):
    EXACT = "exact"
    PREFIX_FUZZY = "prefixFuzzy"
    SUFFIX_FUZZY = "suffixFuzzy"
    PLURAL_TOGGLE = "pluralToggle"
    SYNONYM_EXPANSION = "synonymExpansion"


@dataclass
class ImageMatch:
    key: str
    match_type: MatchType


# Body-part synonyms for token-level replacement (matches Swift synonyms dict)
SYNONYMS = {
    "quadriceps": "quad",
    "quadricep": "quad",
    "hamstrings": "hamstring",
    "calves": "calf",
    "abdominals": "abdominal",
}

# Alias map: AI-generated exercise name variants → canonical image key.
#
# PR 3 deleted the Swift `aliasMap` this used to mirror. Aliases now live in
# `scripts/output/all_exercises_metadata.json` (per-entry `aliases` arrays) and
# are propagated into `exercise_image_mapping.json` by `rebuild_image_mapping.py`.
#
# This stub is kept empty so existing imports of `ALIAS_MAP` from this module
# don't break. New Python code should read aliases from the metadata JSON
# instead. To migrate fully: refactor callers to load aliases dynamically and
# delete this constant.
ALIAS_MAP: dict[str, str] = {}


def normalize_name(name: str) -> str:
    """Convert exercise name to a normalized filename key.

    Matches ExerciseImageService.normalizeName() in Swift exactly:
    - Lowercase
    - Remove apostrophes (both types)
    - Split on non-alphanumeric-non-hyphen chars
    - Join with hyphens
    """
    name = name.lower()
    name = name.replace("'", "").replace("\u2019", "")  # straight + curly apostrophe
    # Split on anything that's not alphanumeric or hyphen
    tokens = re.split(r"[^a-z0-9\-]+", name)
    tokens = [t for t in tokens if t]
    return "-".join(tokens)


def _longest_prefix_match(name: str, mapping_keys: set) -> Optional[str]:
    """Find a mapping key with a prefix-relationship to `name` at a hyphen boundary.

    Bidirectional:
    - Forward (key ⊂ name): `name.startswith(key + "-")` — AI tacked qualifiers onto a
      known canonical name. Prefers longest (most specific) key.
    - Reverse (name ⊂ key): `key.startswith(name + "-")` — AI generated a shorter
      phrasing of an existing variant. Prefers shortest (least specialized) key.

    Forward direction is tried first to preserve prior behavior for the common case.
    """
    forward = [k for k in mapping_keys if name.startswith(k + "-")]
    if forward:
        return max(forward, key=len)
    reverse = [k for k in mapping_keys if k.startswith(name + "-")]
    return min(reverse, key=len) if reverse else None


def _suffix_match(name: str, mapping_keys: set) -> Optional[str]:
    """Find a mapping key with a suffix-relationship to `name` at a hyphen boundary.

    Bidirectional:
    - Forward — AI gave a SHORTER form than canonical, canonical added a prefix.
      `key.endswith("-" + name)`. e.g. name="calf-raises" → key="standing-calf-raises".
    - Reverse — AI gave a LONGER form than canonical, AI added a prefix.
      `name.endswith("-" + key)`. e.g. name="supine-clamshells" → key="clamshells".

    Both prefer the shortest match (least specialized). Forward fires first.
    """
    forward = [k for k in mapping_keys if k.endswith("-" + name)]
    if forward:
        return min(forward, key=len)
    reverse = [k for k in mapping_keys if name.endswith("-" + k)]
    return min(reverse, key=len) if reverse else None


def _apply_synonyms(name: str) -> str:
    """Replace body-part synonym tokens in a hyphen-delimited name."""
    tokens = name.split("-")
    changed = False
    for i, token in enumerate(tokens):
        if token in SYNONYMS:
            tokens[i] = SYNONYMS[token]
            changed = True
    return "-".join(tokens) if changed else name


class FuzzyMatcher:
    """7-layer exercise image fuzzy matcher.

    Mirrors ExerciseImageService.resolveImageMatch() logic.
    """

    def __init__(self, mapping: dict, alias_map: Optional[dict] = None):
        """
        Args:
            mapping: exercise_image_mapping.json dict (key → ImageEntry)
            alias_map: optional override for alias map (default: use built-in ALIAS_MAP)
        """
        self.mapping_keys = set(mapping.keys())
        self.alias_map = alias_map if alias_map is not None else ALIAS_MAP
        self._cache: dict[str, Optional[ImageMatch]] = {}

    @classmethod
    def from_mapping_file(cls, mapping_path: Optional[str] = None) -> "FuzzyMatcher":
        """Create a FuzzyMatcher from the exercise_image_mapping.json file."""
        if mapping_path is None:
            mapping_path = str(
                Path(__file__).parent / "output" / "exercise_image_mapping.json"
            )
        with open(mapping_path) as f:
            mapping = json.load(f)
        return cls(mapping)

    def resolve(
        self,
        exercise_name: str,
        image_file_name: Optional[str] = None,
    ) -> Optional[ImageMatch]:
        """Resolve an exercise name to an image key using 7-layer matching.

        Args:
            exercise_name: Display name (e.g., "Quad Sets")
            image_file_name: Optional explicit imageFileName from AI
        """
        # Layer 1: Explicit imageFileName
        if image_file_name and image_file_name in self.mapping_keys:
            return ImageMatch(key=image_file_name, match_type=MatchType.EXACT)

        # Layer 2: Normalized name
        normalized = normalize_name(exercise_name)
        if normalized in self.mapping_keys:
            return ImageMatch(key=normalized, match_type=MatchType.EXACT)

        # Layer 3: Alias map
        alias_target = self.alias_map.get(normalized)
        if alias_target and alias_target in self.mapping_keys:
            return ImageMatch(key=alias_target, match_type=MatchType.EXACT)

        # Layers 4-7: Fuzzy (cached on the normalized name)
        if normalized in self._cache:
            return self._cache[normalized]

        result = self._fuzzy_match(normalized)

        # Layer 4b: Retry fuzzy on the AI-provided imageFileName.
        # The AI often produces a high-quality kebab-case `imageFileName` that's a
        # single transformation off canonical (plural toggle, prefix modifier, suffix
        # qualifier). Layer 1 only does exact-match on imageFileName, so a near-correct
        # guess is otherwise discarded. Feed it back into the fuzzy layers.
        if result is None and image_file_name and image_file_name != normalized:
            result = self._fuzzy_match(image_file_name)

        self._cache[normalized] = result
        return result

    def _fuzzy_match(self, normalized: str) -> Optional[ImageMatch]:
        """Layers 4-7: progressively looser matching."""
        # Layer 4: Longest prefix match
        match = _longest_prefix_match(normalized, self.mapping_keys)
        if match:
            return ImageMatch(key=match, match_type=MatchType.PREFIX_FUZZY)

        # Layer 5: Suffix match
        match = _suffix_match(normalized, self.mapping_keys)
        if match:
            return ImageMatch(key=match, match_type=MatchType.SUFFIX_FUZZY)

        # Layer 6: Plural/singular toggle, then retry 4-5
        toggled = normalized.rstrip("s") if normalized.endswith("s") else normalized + "s"
        if toggled in self.mapping_keys:
            return ImageMatch(key=toggled, match_type=MatchType.PLURAL_TOGGLE)
        match = _longest_prefix_match(toggled, self.mapping_keys)
        if match:
            return ImageMatch(key=match, match_type=MatchType.PLURAL_TOGGLE)
        match = _suffix_match(toggled, self.mapping_keys)
        if match:
            return ImageMatch(key=match, match_type=MatchType.PLURAL_TOGGLE)

        # Layer 7: Synonym expansion, then retry 2+4+5
        expanded = _apply_synonyms(normalized)
        if expanded != normalized:
            if expanded in self.mapping_keys:
                return ImageMatch(key=expanded, match_type=MatchType.SYNONYM_EXPANSION)
            match = _longest_prefix_match(expanded, self.mapping_keys)
            if match:
                return ImageMatch(key=match, match_type=MatchType.SYNONYM_EXPANSION)
            match = _suffix_match(expanded, self.mapping_keys)
            if match:
                return ImageMatch(key=match, match_type=MatchType.SYNONYM_EXPANSION)
            # Also try plural toggle on expanded form
            expanded_toggled = (
                expanded.rstrip("s") if expanded.endswith("s") else expanded + "s"
            )
            if expanded_toggled in self.mapping_keys:
                return ImageMatch(
                    key=expanded_toggled, match_type=MatchType.SYNONYM_EXPANSION
                )
            match = _longest_prefix_match(expanded_toggled, self.mapping_keys)
            if match:
                return ImageMatch(
                    key=match, match_type=MatchType.SYNONYM_EXPANSION
                )
            match = _suffix_match(expanded_toggled, self.mapping_keys)
            if match:
                return ImageMatch(
                    key=match, match_type=MatchType.SYNONYM_EXPANSION
                )

        return None


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python fuzzy_match.py <exercise_name> [image_file_name]")
        print('Example: python fuzzy_match.py "Quad Sets With VMO Focus"')
        sys.exit(1)

    name = sys.argv[1]
    image_fn = sys.argv[2] if len(sys.argv) > 2 else None

    matcher = FuzzyMatcher.from_mapping_file()
    result = matcher.resolve(name, image_fn)

    if result:
        print(f"Match: {result.key} (type: {result.match_type.value})")
    else:
        normalized = normalize_name(name)
        print(f"No match found for '{name}' (normalized: '{normalized}')")
