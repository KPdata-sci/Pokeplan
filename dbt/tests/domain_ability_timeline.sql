-- Nothing has an ability before gen III or a hidden ability before gen V.
SELECT * FROM {{ ref('fact_pokemon_ability') }}
WHERE valid_from_generation < 3 OR (is_hidden AND valid_from_generation < 5)
