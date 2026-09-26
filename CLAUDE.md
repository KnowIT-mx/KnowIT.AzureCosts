# KnowIT.AzureCosts

Contexto para Claude Code. Este archivo se carga solo al abrir la carpeta.
Léelo completo antes de tocar nada: contiene decisiones ya tomadas con razones
que no son obvias en el código, y hechos verificados contra la documentación
de Microsoft que **no hay que volver a investigar**.

## Qué es

Módulo de PowerShell **standalone** de consulta y análisis de costos de Azure:
una versión "curada" de Az.CostManagement, igual de agnóstica pero fácil de
usar. Los comandos devuelven objetos y siguen la filosofía de PowerShell (cada
comando hace una cosa; exportar, agrupar o convertir se hace con los comandos
nativos por pipeline). Es la base de aplicaciones más específicas, que viven en
sus propios repos. Se publicará en PSGallery.

Comandos públicos (prefijo `KnowITAzCosts`): `Get-KnowITAzCostsResourceInventory`,
`Get-KnowITAzCostsDetail`, `Export-KnowITAzCostsRaw`, `Clear-KnowITAzCostsCache`.

**Única dependencia externa: Az.Accounts** (sesión, suscripciones delegadas,
tokens). No agregues otra sin preguntar. **No agregues parámetros `-OutFile`
a los `Get-*`:** el pipeline con `Export-Csv`/`ConvertTo-Json` ya lo resuelve;
solo `Export-*` escribe archivos.

**El módulo no conoce a quien lo consume.** Ninguna aplicación, Function App,
cliente ni forma de acceso particular se menciona en el código ni en la
documentación de este repo. Si algo solo tiene sentido para un consumidor, va
en el repo del consumidor.

## Estándar de módulos KnowIT

Estructura generada por `New-KnowITModule` (de `KnowIT.Builder`); no inventes
otra:

- `src/KnowIT.AzureCosts.psm1`, `src/public/`, `src/private/`.
- `module.psd1` en la raíz: definición para `Build-KnowITModule`.
  `ExternalModules` se vuelve `RequiredModules` en el manifiesto compilado.
- `run.ps1` carga el `.psm1` desde el fuente (se corre desde la raíz);
  `dev-build.ps1` compila a `out/`.
- Funciones públicas con `[CmdletBinding()]`, `Update-CallerPreference`,
  `try/catch` con `$PSCmdlet.WriteError`. Wrapper `Invoke-*` que devuelve un
  objeto Response. Funciones privadas en PascalCase sin guion.
- Verbos y sustantivos de las funciones públicas en inglés conforme a los estandares de PowerShell.
- Codigo y nombre de variables en ingles: variables locales camelCase ($detailData) y variables a nivel script PascalCase ($script:SubscriptionsCache)
- Comentarios y mensajes hacia el usuario en español.
- Pruebas en `tests/`, fuera de `src/` para que no se empaqueten.
- Referencia de comandos en `docs/`, una página por cmdlet al estilo de Microsoft
  Learn (formato PlatyPS) más `about_KnowIT.AzureCosts.md`. **Al cambiar un
  parámetro, actualiza su página y la ayuda comment-based del cmdlet.** La
  sintaxis y los metadatos de cada parámetro se sacan de `Get-Command`, no a mano.

## Decisiones tomadas y por qué

**Cost Details API, no el export nativo.** Se genera a demanda, sin crear
storage ni exports en la suscripción.

**Caché local transparente en `~/.Azure/KnowIT.AzureCosts/<suscripción>/`.** La
API está limitada (~1 consulta al día por suscripción) y no filtra por resource
group, así que ante un faltante se descarga el mes completo de la suscripción y
todos los filtros se aplican localmente. Cada usuario tiene el suyo; un caché
compartido queda para después. Vigencias: mes cerrado permanente si se
descargó ≥5 días después del cierre; mes en curso o recién cerrado, 24 h;
inventario, un archivo por día (se borran los de días anteriores). `-Force`
ignora el caché. Cada mes tiene un manifiesto JSON que se escribe al final: un
CSV sin manifiesto es una descarga interrumpida y no cuenta.

**Tags: cuáles usa cada comando.** Inventario: los de hoy. `Detail`: los de hoy
si el recurso existe (son los que alguien va a corregir), si no los del cargo.
`Raw`: los del día del cargo; `-TagsFromInventory` usa los de hoy. `-Untagged`
es "sin ningún tag" y excluye a `-ResourceGroup` y `-Tag`. `Tags` es hashtable
(para filtrar); `-TagsAsJson` (inventario y `Detail`) la convierte al final en
JSON compacto con llaves en orden ordinal, porque `Export-Csv` escribe
`System.Collections.Hashtable`. Columnas de tags con
el nombre tal cual; solo si chocan con una propiedad o columna se les antepone
`tag_`.

**Periodos.** `-Month` (alias `-Period`, varios meses) o `-StartDate`/`-EndDate`.
`Detail` devuelve una fila por recurso por mes. `-SubscriptionId` es obligatorio
en `Detail`/`Raw` (cada suscripción es una llamada a la API que tarda minutos)
y opcional en el inventario (sin él, todas las accesibles: ARG es barato).

**Autocompletado de `-Tag` y `-TagColumn` con `Register-ArgumentCompleter`**,
no con `[ArgumentCompleter()]`: en el módulo compilado el scriptblock del
atributo no queda ligado al módulo y no ve las funciones privadas.

**El cruce entre costos e inventario es por ResourceId en minúsculas.** ARG
devuelve `/resourcegroups/` en minúsculas; el detalle usa `/resourceGroups/`.
Bug #1 de este tipo de pipeline; cubierto por pruebas.

**Los resource groups se agrupan sin distinguir mayúsculas.** Los recursos
borrados traen el casing del CSV y los vigentes el de ARG; sin normalizar, un
mismo RG sale partido en varias filas. Pasó con datos reales.

**El mapeo de columnas tolera FOCUS y ActualCost legacy**, sin distinguir
mayúsculas (la Cost Details API entrega camelCase). Difieren en costo
(`EffectiveCost` vs `CostInBillingCurrency`), resource group
(`x_ResourceGroupName` vs `ResourceGroup`) y sobre todo en tags: **FOCUS
entrega JSON con llaves, el legacy SIN llaves envolventes**.

**Los nombres de tag no distinguen mayúsculas**, como en Azure. Los
diccionarios de tags son `@{}` (case-insensitive); no los cambies por un tipo
que distinga.

**Pipelines y triggers de Data Factory se suman a su factory** y toman sus
tags. Tienen ResourceId propio con costo pero ARG no los inventaría. Es una
lista explícita (`ChildToParentTypes`), no una regla genérica: una base SQL
que no está en ARG es una base borrada y debe seguir visible como tal.

**El export crudo escribe el CSV directo** con `StreamWriter`, en el mismo
formato que `Export-Csv`: crear un PSCustomObject por fila (20 mil filas × 60
columnas en un mes real) es varias veces más lento.

**Orden ordinal (`SortOrdinal`) donde el orden importa.** `Sort-Object` usa
reglas de la cultura y ordena distinto según la máquina.

**Trampas de PowerShell que ya mordieron:**
- Una variable local `$resourceGroup` es la misma que el parámetro
  `-ResourceGroup` (no distingue mayúsculas) y pisa el filtro.
- `Nullable[datetime]` se desenvuelve solo: `.Value` devuelve `$null`.
- `"texto".StartsWith("`0")` es verdadero siempre con comparación cultural
  (ICU ignora el nulo): usar `[StringComparison]::Ordinal`.
- `$null | ForEach-Object` corre una vez; usar `foreach` cuando la colección
  puede ser nula.
- `Update-CallerPreference` (helper estándar) busca la llave `Warning` y no
  `WarningAction`, así que `-WarningAction` no surte efecto; y su
  `Set-Variable` obedece `-WhatIf` (por eso `Clear-KnowITAzCostsCache` apaga
  `$WhatIfPreference` mientras lo llama).

**`-ErrorVariable` no sirve para contar errores en las pruebas.** También junta
los que la función atrapa en su propio `try/catch`. Las pruebas cuentan los
`ErrorRecord` del stream (`2>&1`) con `-ErrorAction Continue` explícito:
`Update-CallerPreference` toma la preferencia del script, no de una función
auxiliar.

## Estado de verificación

| Componente | Estado |
|---|---|
| `tests/Verificar.ps1` | 92 verificaciones con datos sintéticos en un caché temporal, sin Azure; esperados calculados por separado. Pasan |
| `tests/Probar-Azure.ps1` | Pasa contra una suscripción CSP real con acceso delegado (sept 2026): ~1,500 recursos con paginación correcta, 17 suscripciones sin `-SubscriptionId`, detalle desde caché cuadra con los totales ya validados, export crudo de 20,709 filas en ~2 s y suma igual que el detalle |
| Descarga de la Cost Details API | Probada de punta a punta en la iteración anterior (202, sondeo, manifiesto, CSV de 21 MB); la lógica pasó igual a `SaveCostDetailReport` |
| Compilado con `dev-build.ps1` | Importa por nombre, exporta los 4 comandos, autocompletado funciona |

## Hechos ya verificados — no re-investigar

- Cost Details API: solo EA y MCA (incluye CSP), no pay-as-you-go. Máx 1 mes
  por reporte, máx 13 meses de antigüedad, rate limited (Microsoft pide ≤1
  consulta/día; los datos se refrescan cada 4 h), solo CSV, **no soporta
  scope de resource group ni management group**, solo `ActualCost` o
  `AmortizedCost`, nunca FOCUS. Responde 202 + `Location` + `Retry-After`;
  los `blobLink` del manifiesto traen SAS.
- Permisos: para costos a scope de suscripción Microsoft pide al menos Cost
  Management Reader (o Contributor); el inventario de ARG necesita Reader
  aparte. Asignar roles requiere User Access Administrator u Owner.
- CSP: el partner debe activar la política de cost visibility por cliente;
  sin ella la API devuelve 403. Con ella, cualquier usuario con RBAC sobre la
  suscripción (del tenant del cliente o por Lighthouse) ve costos a precio
  retail de pay-as-you-go, sin descuentos ni créditos del partner.
- Azure Lighthouse solo aplica a llamadas de `management.azure.com`, no a data
  plane. Soporta roles built-in excepto Owner y los que tienen DataActions.
- Tag inheritance existe para EA/MCA/MPA, **no** para pay-as-you-go. No es
  retroactivo más allá del mes en curso. Por default el tag del recurso gana
  sobre el heredado. No se configura por ARM.
- Roles: Reader `acdd72a7-3385-48ef-bd42-f606fba81ae7`,
  Cost Management Reader `72fafb9e-0641-4937-9268-a91bfd8191a3`,
  Tag Contributor `4a9ae827-6dc8-4573-8ac7-8239d42aa03f`.
- CSV real de la Cost Details API (CSP): fecha `MM/dd/yyyy`, resource group
  en `resourceGroupName`, tags como JSON con llaves.

## Convenciones

- Los comentarios explican **por qué**, no qué.
- Nada de connection strings ni llaves: todo por la sesión de
  `Connect-AzAccount` (usuario o managed identity).
- Antes de sugerir un comando o parámetro de Azure, verifícalo. Por eso hay
  una sección de hechos verificados.
- Datos reales solo en `salidas/` o en el caché, nunca en el repo.
