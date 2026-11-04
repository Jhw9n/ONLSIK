#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
folder="$(mktemp -d "${TMPDIR:-/tmp}/oneulsik-benchmark.XXXXXX")"
cp ONEULSIK/Resource/Data/FoodCatalog.sqlite ONEULSIK/Resource/Data/FoodReferences.json "$folder/"
xcrun swiftc -D DEBUG -O -swift-version 5 -default-isolation MainActor -parse-as-library \
    ONEULSIK/Models/FoodReference.swift ONEULSIK/Models/MealEntryDraft.swift \
    ONEULSIK/Models/MealRecord.swift ONEULSIK/Models/MealType.swift \
    ONEULSIK/Models/FoodCatalogItem.swift ONEULSIK/Models/FoodPortion.swift \
    ONEULSIK/Models/UserProfile.swift ONEULSIK/Stores/MealRecordStore.swift \
    ONEULSIK/Services/MealPerformance.swift ONEULSIK/Services/AIMealEntryService.swift \
    ONEULSIK/Services/AppleMealFoodInterpreter.swift ONEULSIK/Services/MealInputGrounding.swift \
    ONEULSIK/Services/FoodCatalogService.swift Scripts/benchmark_meal_entry.swift \
    -o "$folder/benchmark"
echo "Benchmark files: $folder"
ONEULSIK_METRICS_STDOUT=1 "$folder/benchmark" --output "$folder/search.json" "$@"
