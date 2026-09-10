CREATE SCHEMA IF NOT EXISTS `bronze`
  OPTIONS (
    location = '${LOCATION}',
    description = 'Camada Bronze. Cópia fiel da fonte pública, recorte 2020.'
  );

CREATE SCHEMA IF NOT EXISTS `silver`
  OPTIONS (
    location = '${LOCATION}',
    description = 'Camada Silver. Dados desaninhados, limpos e enriquecidos.'
  );

CREATE SCHEMA IF NOT EXISTS `gold`
  OPTIONS (
    location = '${LOCATION}',
    description = 'Camada Gold. Matriz de features e resultados do modelo.'
  );
