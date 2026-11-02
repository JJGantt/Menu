#!/usr/bin/env bash
# Fetch the app's data from Supabase into Seed/ (gitignored), which the build bundles: what a fresh
# install shows before its first fetch lands, e.g. a tester updating at work on a weak signal. Each
# file is named by the cache key the app reads it under (SupabaseClient.getCached), with the same
# query the app makes, using the same publishable key (from Secrets.swift), so it is exactly what the
# app itself would have saved. release.sh runs this before archiving.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY=$(grep -o 'sb_publishable_[A-Za-z0-9_-]*' MenuApp/Secrets.swift | head -1)
[ -n "$KEY" ] || { echo "seed: no publishable key in MenuApp/Secrets.swift" >&2; exit 1; }
BASE=$(awk -F'"' '/static let projectURL/ {print $2}' MenuApp/SupabaseClient.swift)/rest/v1/

# cache key | path — keep in step with the getCached calls in the app.
READS='
menu_groups|menu_groups?select=id,title,sort,sections&order=sort.asc
menu_dishes|menu_dishes?select=*&order=menu.asc,sort.asc
seasonal_programs|app_content?key=eq.seasonal_programs&select=data
cocktails|cocktails?select=*&order=sort.asc
system_prompt|app_content?key=eq.system_prompt&select=data
app_config|app_config?select=profile,allowed_models,default_model,restaurant_name
bottles|bottles?select=*&deleted=eq.false&unverified=eq.false
bottle_areas|bottle_areas?select=*&order=name.asc
section_views|section_views?select=*&order=sort_order.asc
spirit_types|spirit_types?select=*
group_descriptions|group_descriptions?select=*
style_pairings|style_pairings?select=*
glossary|glossary?select=*
menu_dish_names|menu_dishes?select=id,name
'

rm -rf Seed.tmp && mkdir Seed.tmp
while IFS='|' read -r key path; do
    [ -n "$key" ] || continue
    curl -sf "$BASE$path" -H "apikey: $KEY" -o "Seed.tmp/$key.json"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d,list) and d, "empty"' "Seed.tmp/$key.json" \
        || { echo "seed: $key came back empty or invalid" >&2; exit 1; }
done <<< "$READS"
touch Seed.tmp/.gitkeep
rm -rf Seed && mv Seed.tmp Seed
echo "seed: $(ls Seed | wc -l | tr -d ' ') files in Seed/"
