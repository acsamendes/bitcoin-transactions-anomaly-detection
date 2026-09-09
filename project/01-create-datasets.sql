CREATE SCHEMA IF NOT EXISTS `trabalho1-pdm-2026.bronze`
  OPTIONS (
    location = 'US',
    description = 'Camada Bronze. Cópia fiel da fonte pública, recorte 2020.'
  );

CREATE SCHEMA IF NOT EXISTS `trabalho1-pdm-2026.silver`
  OPTIONS (
    location = 'US',
    description = 'Camada Silver. Dados desaninhados, limpos e enriquecidos.'
  );

CREATE SCHEMA IF NOT EXISTS `trabalho1-pdm-2026.gold`
  OPTIONS (
    location = 'US',
    description = 'Camada Gold. Matriz de features e resultados do modelo.'
  );
