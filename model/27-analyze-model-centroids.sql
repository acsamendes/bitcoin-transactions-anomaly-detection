SELECT
  centroid_id,
  feature,
  ROUND(numerical_value, 3) AS valor
FROM ML.CENTROIDS(MODEL `gold.kmeans_k8_10pct`)
ORDER BY centroid_id, feature;
