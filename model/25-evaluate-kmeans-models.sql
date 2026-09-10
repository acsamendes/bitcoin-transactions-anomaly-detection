SELECT 'K=3  | amostra 1%'   AS modelo, 3  AS k, '1%'   AS amostra,
       ROUND(davies_bouldin_index, 4) AS davies_bouldin,
       ROUND(mean_squared_distance, 4) AS dist_quadratica
FROM ML.EVALUATE(MODEL `gold.kmeans_k3`)
UNION ALL
SELECT 'K=5  | amostra 1%', 5, '1%',
       ROUND(davies_bouldin_index, 4), ROUND(mean_squared_distance, 4)
FROM ML.EVALUATE(MODEL `gold.kmeans_k5`)
UNION ALL
SELECT 'K=6  | amostra 1%', 6, '1%',
       ROUND(davies_bouldin_index, 4), ROUND(mean_squared_distance, 4)
FROM ML.EVALUATE(MODEL `gold.kmeans_k6`)
UNION ALL
SELECT 'K=8  | amostra 1%', 8, '1%',
       ROUND(davies_bouldin_index, 4), ROUND(mean_squared_distance, 4)
FROM ML.EVALUATE(MODEL `gold.kmeans_k8_1pct`)
UNION ALL
SELECT 'K=12 | amostra 1%', 12, '1%',
       ROUND(davies_bouldin_index, 4), ROUND(mean_squared_distance, 4)
FROM ML.EVALUATE(MODEL `gold.kmeans_k12`)
UNION ALL
SELECT 'K=8  | amostra 10%', 8, '10%',
       ROUND(davies_bouldin_index, 4), ROUND(mean_squared_distance, 4)
FROM ML.EVALUATE(MODEL `gold.kmeans_k8_10pct`)
UNION ALL
SELECT 'K=8  | base completa', 8, '100%',
       ROUND(davies_bouldin_index, 4), ROUND(mean_squared_distance, 4)
FROM ML.EVALUATE(MODEL `gold.kmeans_k8_full`)
ORDER BY davies_bouldin;
