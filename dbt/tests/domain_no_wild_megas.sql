-- Battle-only transformations are never found in the wild. The one
-- exception is real: Gigantamax Pokémon are met in Sword/Shield Max Raids.
SELECT p.pokemon_code, m.encounter_method_code, count(*) AS encounters
FROM {{ ref('fact_encounter') }} f
JOIN {{ ref('dim_pokemon') }} p USING (pokemon_key)
JOIN {{ ref('dim_encounter_method') }} m USING (encounter_method_key)
WHERE p.form_category IN ('mega', 'primal', 'gigantamax') AND m.method_group <> 'raid'
GROUP BY 1, 2
