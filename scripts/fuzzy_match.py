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
# Mirrors ExerciseImageService.swift aliasMap exactly.
ALIAS_MAP = {
    "calf-raises-bilateral-eccentric-focus": "double-leg-calf-raise",
    "calf-raises-bilateral-to-single-leg-progression": "double-leg-calf-raise",
    "calf-raises-double-leg-eccentric-emphasis": "double-leg-calf-raise",
    "calf-raise-with-hamstring-co-activation-weeks-3-6": "double-leg-calf-raise",
    "calf-raises-bilateral": "double-leg-calf-raise",
    "band-pull-apart": "band-pull-aparts",
    "half-kneeling-band-pull-aparts": "band-pull-aparts",
    "band-pull-apart-external-rotation": "resistance-band-external-rotation-at-90-90",
    "bird-dog-core-stabilizer": "bird-dog",
    "quadruped-bird-dog": "bird-dog",
    "quadruped-spinal-extensions-bird-dogs": "bird-dog",
    "childs-pose-with-shoulder-reach": "childs-pose-with-side-reach",
    "cat-cow-stretch-modified-for-lower-back-relief": "cat-cow-stretch",
    "cat-cow-stretch-prone-hold-variation": "cat-cow-stretch",
    "cat-cow-stretch-sequence": "cat-cow-stretch",
    "cat-cow-stretch-spine-mobility": "cat-cow-stretch",
    "clamshells-left-side-emphasis": "clamshells",
    "clamshells-side-lying-hip-abduction": "clamshells",
    "dead-bug-modified-for-core-stability-and-l4-protection": "dead-bug",
    "dead-bug-core-stability-for-lower-back-support": "dead-bug",
    "dead-bug-core-stability-hamstring-protection": "dead-bug",
    "dead-bug-modified": "dead-bug",
    "glute-bridge-with-core-hold": "glute-bridge-with-isometric-hold",
    "supine-glute-bridge-with-hamstring-activation": "glute-bridge",
    "glute-bridge-with-hamstring-engagement": "glute-bridge",
    "glute-bridges-bilateral": "glute-bridges",
    "supine-hip-bridge": "glute-bridge",
    "banded-glute-kickbacks-standing-hip-extension": "standing-hip-extension",
    "hamstring-and-calf-stretch-supine-strap-assist": "hamstring-stretch-with-strap",
    "supine-hamstring-stretch-with-strap": "hamstring-stretch-with-strap",
    "seated-forward-fold-hamstring-stretch": "seated-hamstring-stretch",
    "lying-hamstring-and-hip-flexor-stretch-modified": "lying-hip-flexor-stretch",
    "hamstring-stretch": "supine-hamstring-stretch",
    "supine-hamstring-stretch-with-towel-strap": "supine-hamstring-stretch",
    "nordic-hamstring-curl-assisted-weeks-4-6": "hamstring-curls",
    "standing-hamstring-flexibility-walk": "walking",
    "lateral-band-walk-glute-medius-hip-stability": "lateral-band-walks",
    "monster-walks-resistance-band": "monster-walks",
    "pendulum-shoulder-circles": "pendulum-swings",
    "right-shoulder-pendulum-circles": "pendulum-swings",
    "seated-shoulder-pendulum-circles": "pendulum-swings",
    "plantar-fascia-and-soleus-stretch": "soleus-stretch",
    "planks-modified-wall-or-incline": "plank",
    "prone-plank-hold-beginner-progression": "plank",
    "tall-plank-with-shoulder-blade-protraction": "plank",
    "prone-hamstring-isometric-hold": "prone-hamstring-curl",
    "prone-hip-extension-single-leg-for-glute-activation": "prone-hip-extension",
    "prone-hip-extension-single-leg": "prone-hip-extension",
    "prone-shoulder-external-rotation-with-elbow-support": "side-lying-external-rotation",
    "prone-shoulder-i-y-t-raises": "prone-i-y-t-raises",
    "prone-y-t-w-shoulder-activation": "prone-i-y-t-raises",
    "lower-back-quadriceps-tightness---prone-quad-stretch": "standing-quad-stretch",
    "prone-cobra-modified-sphinx": "prone-press-up",
    "prone-cobra-or-modified-sphinx-lower-back-extension": "prone-press-up",
    "prone-sphinx-stretch": "prone-press-up",
    "prone-scapular-squeeze": "prone-scapular-retraction",
    "prone-hip-internal-rotation-piriformis-stretch": "supine-piriformis-stretch",
    "prone-quadriceps-stretch": "standing-quad-stretch",
    "quad-sets-with-glute-activation": "quad-sets",
    "quad-sets-with-vmo-focus": "quad-sets",
    "quadriceps-sets-isometric": "quad-sets",
    "quadriceps-sets-with-vmo-focus": "quad-sets",
    "quadriceps-sets-bilateral": "quad-sets",
    "quadriceps-strengthening": "quad-sets",
    "quadriceps-and-patellar-tendon-eccentric-stretch": "standing-quad-stretch",
    "quadriceps-eccentric-lowering-controlled-strength": "long-arc-quads",
    "quadriceps-stretch": "standing-quad-stretch",
    "quadriceps-stretch-standing": "standing-quad-stretch",
    "quadriceps-hip-flexor-stretch-kneeling-lunge": "hip-flexor-stretch",
    "quadruped-cat-cow-stretch": "cat-cow-stretch",
    "thoracic-spine-rotation-quadruped-cat-cow": "quadruped-thoracic-rotation",
    "quadruped-glute-squeeze-activation-endurance": "prone-glute-squeeze-holds",
    "quadruped-hip-extension-glute-activation": "fire-hydrants",
    "quadruped-hip-shoulder-rocks": "quadruped-rocking",
    "quadruped-rocking-with-spinal-extension": "quadruped-rocking",
    "external-rotation-with-elbow-bent-90-90-position": "external-rotation",
    "right-shoulder-external-rotation-prone": "side-lying-external-rotation",
    "scapular-push-up-hold": "wall-push-ups",
    "scapular-push-up-plus": "wall-push-ups",
    "scapular-push-up-plus-modified": "wall-push-ups",
    "serratus-anterior-push-up-plus": "wall-push-ups",
    "scapular-wall-slides": "wall-slides",
    "single-leg-stance-on-firm-surface": "single-leg-balance",
    "single-leg-balance-left-leg-emphasis": "single-leg-balance",
    "single-leg-romanian-deadlift-light-load": "single-leg-deadlift",
    "standing-single-leg-balance-with-hip-hinge": "single-leg-deadlift",
    "standing-hamstring-curl-progressive": "standing-hamstring-curl",
    "standing-chest-doorway-stretch": "doorway-stretch",
    "standing-hip-flexor-stretch": "hip-flexor-stretch",
    "shoulder-rolls": "shoulder-shrugs",
    "straight-leg-raise-slr---supine": "straight-leg-raises",
    "straight-leg-raise-left-leg": "straight-leg-raises",
    "straight-leg-raises-supine": "straight-leg-raises",
    "supine-lower-back-stretch": "knee-to-chest-stretch",
    "supine-lower-back-rotation-stretch": "lumbar-rotation-stretch",
    "supine-lower-back-rotation-stretch-spinal-mobility": "lumbar-rotation-stretch",
    "supine-shoulder-external-rotation-90-90-position": "external-rotation",
    "supine-shoulder-external-rotation-with-towel-roll": "external-rotation",
    "supine-shoulder-flexion-with-dowel-or-pvc-pipe": "shoulder-flexion",
    "supine-hip-flexor-stretch": "lying-hip-flexor-stretch",
    "supine-figure-4-stretch-alternative-piriformis-stretch": "supine-figure-4-stretch-with-pelvic-mobilization",
    "seated-knee-extension-with-asthma-pacing": "seated-knee-extension",
    "eccentric-wrist-extensor-curls": "reverse-wrist-curls",
    "forearm-pronation-supination": "wrist-pronation-supination",
    "isometric-wrist-extensions": "reverse-wrist-curls",
    "isometric-wrist-strengthening-4-direction": "wrist-curls",
    "wrist-flexor-extensor-stretches": "wrist-extensor-stretch",
    "wrist-flexor-stretches": "wrist-flexor-stretch",
    "half-kneeling-thoracic-rotation-with-post": "quadruped-thoracic-rotation",
    "thoracic-spine-extensions": "thoracic-extension",
    "pigeon-pose-deep-hip-flexor-piriformis-stretch": "piriformis-stretch",
    "sural-nerve-glide-neural-mobility-for-sural-nerve-irritation": "sciatic-nerve-glide",
    "terminal-knee-extensions-tke": "terminal-knee-extension",
    "calf-raises": "double-leg-calf-raise",
    "cervical-gentle-rom-neck-mobility-check": "chin-tucks",
    "prone-chin-tucks-cervical-posture-support": "chin-tucks",
    "cross-body-shoulder-stretch": "cross-body-stretch",
    "deep-hip-flexor-quad-stretch-90-90": "hip-flexor-stretch",
    "tall-kneeling-hip-flexor-stretch": "hip-flexor-stretch",
    "hamstring-calf-stretch-standing": "supine-hamstring-stretch",
    "hamstring-sets-isometric": "prone-hamstring-curl",
    "lying-hamstring-stretch-90-90-position": "supine-hamstring-stretch",
    "lateral-band-walk-hip-abductor-activation": "lateral-band-walks",
    "prone-cobra-posterior-chain-extension-low-back-mobility": "prone-press-up",
    "prone-shoulder-blade-squeeze-isometric": "prone-scapular-retraction",
    "prone-shoulder-i-y-t-raises-isometric-hold": "prone-i-y-t-raises",
    "prone-shoulder-retraction-y-raises-prone": "prone-i-y-t-raises",
    "prone-superman-hold": "superman-exercise",
    "quadriceps-foam-roll": "foam-roller-quad",
    "quadriceps-stretch-left-leg-kneeling": "standing-quad-stretch",
    "quadruped-shoulder-blade-squeezes-scapular-stabilization": "quadruped-shoulder-taps",
    "quadruped-shoulder-stability-taps": "quadruped-shoulder-taps",
    "scapular-wall-slides-slow-controlled": "wall-slides",
    "seated-knee-extensions-right-leg-focus": "seated-knee-extension",
    "sidelying-external-rotation-90-90-position": "side-lying-external-rotation",
    "single-leg-deadlifts-bodyweight": "single-leg-deadlift",
    "single-leg-glute-bridge": "glute-bridge",
    "standing-shoulder-external-rotation-band-free-isometric": "external-rotation",
    "straight-leg-raise-quad-dominant": "straight-leg-raises",
    "upper-back-postural-correction-standing-wall-hold": "wall-slides",
    "wrist-flexion-extension": "wrist-curls",
    "copenhagen-adduction-side-lying-hip-adductor-squeeze": "copenhagen-adduction",
}


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
    """Find the longest mapping key that is a prefix of `name` at a hyphen boundary."""
    matches = [k for k in mapping_keys if name.startswith(k + "-")]
    return max(matches, key=len) if matches else None


def _suffix_match(name: str, mapping_keys: set) -> Optional[str]:
    """Find a mapping key where `name` appears as a suffix at a hyphen boundary.
    Prefers the shortest (least specialized) key on ambiguity."""
    matches = [k for k in mapping_keys if k.endswith("-" + name)]
    return min(matches, key=len) if matches else None


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

        # Layers 4-7: Fuzzy (cached)
        if normalized in self._cache:
            return self._cache[normalized]

        result = self._fuzzy_match(normalized)
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
