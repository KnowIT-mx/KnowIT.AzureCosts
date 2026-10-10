# KnowIT.AzureCosts

Contexto para Claude Code. Este archivo se carga solo al abrir la carpeta.
Léelo completo antes de tocar nada: contiene decisiones ya tomadas con razones
que no son obvias en el código, y hechos verificados contra la documentación
de Microsoft que **no hay que volver a investigar**.

## Qué es

Módulo de PowerShell **standalone** de consulta y análisis de costos de Azure
por suscripción, resource group, recurso y tag: una alternativa "curada" a
Az.CostManagement, igual de agnóstica pero fácil de usar. Los comandos devuelven
objetos y siguen la filosofía de PowerShell: cada comando hace una cosa, y
exportar, agrupar o convertir se hace con los comandos nativos por pipeline.
Solo lee: no crea ni modifica nada en Azure.

Comandos públicos (prefijo `KnowITAzCosts`):

| Comando | Qué hace |
|---|---|
| `Get-KnowITAzCostsResourceInventory` | Recursos de una o varias suscripciones con sus tags, desde Azure Resource Graph |
| `Get-KnowITAzCostsDetail` | Costo por recurso y por mes, desde la Cost Details API |
| `Export-KnowITAzCostsRaw` | CSV con el detalle diario tal como lo entrega la API, con los tags en columnas |
| `Clear-KnowITAzCostsCache` | Borra el caché local |

**Es un módulo público, distribuido por PowerShell Gallery.** En el código, la
documentación, las pruebas y este archivo no va nada de quien lo usa ni de su
operación: ni clientes, ni suscripciones o tenants reales, ni aplicaciones que
lo consumen, ni formas de acceso particulares. Lo único propio de KnowIT es la
autoría del proyecto y su estándar de módulos. Los ejemplos usan valores
genéricos (`<tenant>`, GUIDs en ceros, tags `Environment`, `Owner`, `CostCenter`).

**Única dependencia externa: Az.Accounts** (sesión, suscripciones delegadas,
tokens). No agregues otra sin preguntar.

**Solo `Export-*` escribe archivos.** No agregues parámetros `-OutFile` a los
`Get-*`: el pipeline con `Export-Csv` o `ConvertTo-Json` ya lo resuelve.

## Estándar de módulos KnowIT

Estructura generada por `New-KnowITModule` (de `KnowIT.Builder`); no inventes
otra:

- `src/KnowIT.AzureCosts.psm1`, `src/public/`, `src/private/`.
- `module.psd1` en la raíz: definición para `Build-KnowITModule`.
  `ExternalModules` se vuelve `RequiredModules` en el manifiesto compilado.
- `run.ps1` carga el `.psm1` desde el fuente (se corre desde la raíz);
  `dev-build.ps1` compila a `out/`.
- Funciones públicas con `[CmdletBinding()]`, `Update-CallerPreference` y
  `try/catch` con `$PSCmdlet.WriteError`. Funciones privadas en PascalCase sin
  guion; lanzan excepción y la pública la emite.
- Verbos y sustantivos de las funciones públicas en inglés conforme a los estandares de PowerShell.
- Codigo y nombre de variables en ingles: variables locales camelCase ($detailData) y variables a nivel script PascalCase ($script:SubscriptionsCache)
- Comentarios y mensajes hacia el usuario en español.
- Pruebas en `tests/`, fuera de `src/` para que no se empaqueten.
- Referencia de comandos en `docs/`, una página por cmdlet al estilo de Microsoft
  Learn (formato PlatyPS) más `about_KnowIT.AzureCosts.md`. **Al cambiar un
  parámetro, actualiza su página y la ayuda comment-based del cmdlet.** La
  sintaxis y los metadatos de cada parámetro se sacan de `Get-Command`, no a mano.

## Cómo funciona y por qué

**Cost Details API, no el export nativo de Cost Management.** Se genera a
demanda, sin crear storage ni exports en la suscripción.

**Caché local transparente en `~/.knowit/KnowIT.AzureCosts/<suscripción>/`.**
Una carpeta propia en el perfil del usuario, no dentro de la de otra
herramienta. La API está limitada (~1 consulta al día por suscripción) y no
filtra por resource group, así que ante un faltante se descarga el mes completo
de la suscripción y todos los filtros se aplican localmente. Cada usuario tiene
su caché.

| Dato | Archivo | Vigencia |
|---|---|---|
| Detalle de un mes | `cost-<métrica>-<yyyy-MM>-partN.csv` y su manifiesto `.json` | Permanente si se descargó ≥5 días después del cierre del mes; si no, 24 h |
| Inventario | `inventory-<yyyy-MM-dd>.json` | El día; al guardar uno nuevo se borran los anteriores |

El manifiesto se escribe al final: un CSV sin manifiesto es una descarga
interrumpida y no cuenta. Un mes sin datos también deja manifiesto, para no
volver a preguntar. `-Force` ignora el caché.

**Periodos.** `-Month` (alias `-Period`, varios meses) o `-StartDate`/`-EndDate`.
El caché siempre guarda meses completos; un rango recorta las filas después.
`Detail` devuelve una fila por recurso por mes. `-SubscriptionId` es obligatorio
en `Detail` y `Raw` (cada suscripción es una llamada a la API que tarda minutos)
y opcional en el inventario (sin él, todas las accesibles: ARG es barato).

**Tags: cuáles usa cada comando.**

| Comando | Tags |
|---|---|
| Inventario | Los de hoy |
| `Detail` sin split | El "más actualizado": si el recurso existe, los de hoy **aunque esté sin tags**; si fue borrado, los últimos con valor del periodo **por fecha** (la API no entrega las filas en orden de fecha) |
| `Detail -SplitByTagChange` | Una fila por juego de tags histórico, con `FirstDate`/`LastDate`. Los días sin tags son un juego más y sí parten el recurso |
| `Raw` | Los del día del cargo; `-TagsFromInventory` usa los de hoy |

- Los nombres de tag no distinguen mayúsculas, como en Azure. Los diccionarios
  de tags son `@{}` (case-insensitive); no los cambies por un tipo que distinga.
- Un tag con valor vacío no cuenta como tag. `-Untagged` es "sin ningún tag" y
  excluye a `-ResourceGroup` y `-Tag`.
- `Tags` es hashtable, para filtrar. `-TagsAsJson` (inventario y `Detail`) la
  convierte al final en JSON compacto con llaves en orden ordinal, porque
  `Export-Csv` escribiría `System.Collections.Hashtable`.
- Columnas de tags (`-TagColumn`) con el nombre tal cual; solo si chocan con una
  propiedad o columna existente se les antepone `tag_`.
- El autocompletado de `-Tag` y `-TagColumn` se registra con
  `Register-ArgumentCompleter`, no con `[ArgumentCompleter()]`: en el módulo
  compilado el scriptblock del atributo no queda ligado al módulo y no ve las
  funciones privadas.

**El cruce entre costos e inventario es por ResourceId en minúsculas.** ARG
devuelve `/resourcegroups/` en minúsculas; el detalle usa `/resourceGroups/`.
Es el error más común de este tipo de cruce; cubierto por pruebas.

**Los resource groups se comparan sin distinguir mayúsculas.** Los recursos
borrados traen el casing del detalle y los vigentes el de ARG.

**El mapeo de columnas tolera FOCUS y ActualCost legacy**, sin distinguir
mayúsculas (la Cost Details API entrega camelCase). Difieren en costo
(`EffectiveCost` vs `CostInBillingCurrency`), resource group
(`x_ResourceGroupName` vs `ResourceGroup`) y sobre todo en tags: **FOCUS
entrega JSON con llaves, el legacy puede venir SIN llaves envolventes**.

**Pipelines y triggers de Data Factory se suman a su factory.** Tienen
ResourceId propio con costo pero ARG no los inventaría. Es una lista explícita
(`ChildToParentTypes`), no una regla genérica: una base SQL que no está en ARG
es una base borrada y debe seguir visible como tal. Con `-SplitByTagChange`
llevan los tags que su factory tuvo ese día.

**Los cargos sin ResourceId** (Marketplace, soporte, reservas) salen en `Detail`
como filas sin recurso, agrupados por servicio y tipo de cargo, para no
perderlos del total.

**El export crudo escribe el CSV directo** con `StreamWriter`, en el mismo
formato que `Export-Csv`: crear un PSCustomObject por fila es varias veces más
lento con decenas de miles de filas.

**Orden ordinal (`SortOrdinal`) donde el orden importa.** `Sort-Object` usa
reglas de la cultura y ordena distinto según la máquina.

## Trampas de PowerShell en este código

- Una variable local `$resourceGroup` es la misma que el parámetro
  `-ResourceGroup` (no distingue mayúsculas) y pisa el filtro.
- `Nullable[datetime]` se desenvuelve solo: `.Value` devuelve `$null`.
- `"texto".StartsWith("`0")` es verdadero siempre con comparación cultural
  (ICU ignora el nulo): usar `[StringComparison]::Ordinal`.
- `$null | ForEach-Object` corre una vez; usar `foreach` cuando la colección
  puede ser nula.
- `Update-CallerPreference` (helper de la plantilla) busca la llave `Warning` y
  no `WarningAction`, así que `-WarningAction` no surte efecto; y su
  `Set-Variable` obedece `-WhatIf` (por eso `Clear-KnowITAzCostsCache` apaga
  `$WhatIfPreference` mientras lo llama).
- `-ErrorVariable` no sirve para contar errores: también junta los que la
  función atrapa en su propio `try/catch`. Las pruebas cuentan los
  `ErrorRecord` del stream (`2>&1`) con `-ErrorAction Continue` explícito.

## Pruebas

| Prueba | Qué cubre |
|---|---|
| `tests/Verificar.ps1` | 108 verificaciones de los cuatro comandos con datos sintéticos sembrados en un caché temporal. No toca Azure. Los valores esperados se calcularon por separado, no con el código que se prueba |
| `tests/Probar-Azure.ps1` | Llamadas reales con la sesión de Az activa: paginación de Resource Graph, caché, y que el export crudo sume lo mismo que el detalle. Solo descarga de la Cost Details API con `-IncludeCostDetail`, porque gasta la consulta del día |

Después de un cambio corre `Verificar.ps1` y compila con `dev-build.ps1`: el
módulo compilado debe exportar solo los cuatro comandos.

## Hechos ya verificados — no re-investigar

- Cost Details API: solo EA y MCA (incluye CSP), no pay-as-you-go. Máx 1 mes
  por reporte, máx 13 meses de antigüedad, rate limited (Microsoft pide ≤1
  consulta/día; los datos se refrescan cada 4 h), solo CSV, **no soporta
  scope de resource group ni management group**, solo `ActualCost` o
  `AmortizedCost`, nunca FOCUS. Responde 202 + `Location` + `Retry-After`;
  los `blobLink` del manifiesto traen SAS.
- CSV de la Cost Details API: fecha `MM/dd/yyyy`, resource group en
  `resourceGroupName`, tags como JSON con llaves. Las filas no vienen en orden
  de fecha, y hay días sin tags en recursos que sí los tienen.
- Permisos: para costos a scope de suscripción Microsoft pide al menos Cost
  Management Reader (o Contributor); el inventario de ARG necesita Reader
  aparte. Asignar roles requiere User Access Administrator u Owner.
- CSP: el partner debe activar la política de cost visibility por cliente;
  sin ella la API devuelve 403. Con ella, cualquier usuario con RBAC sobre la
  suscripción ve costos a precio retail de pay-as-you-go, sin descuentos ni
  créditos del partner.
- Azure Lighthouse: el token del tenant que administra sirve para las
  suscripciones delegadas. Solo aplica a llamadas de `management.azure.com`,
  no a data plane.
- Tag inheritance de Cost Management existe para EA/MCA/MPA, no para
  pay-as-you-go, y no es retroactivo más allá del mes en curso. Si está
  activo, los tags del detalle ya lo reflejan.
- Roles: Reader `acdd72a7-3385-48ef-bd42-f606fba81ae7`,
  Cost Management Reader `72fafb9e-0641-4937-9268-a91bfd8191a3`.

## Convenciones

- Los comentarios explican **por qué**, no qué.
- Nada de connection strings ni llaves: todo por la sesión de
  `Connect-AzAccount` (usuario o managed identity).
- Antes de sugerir un comando o parámetro de Azure, verifícalo. Por eso hay
  una sección de hechos verificados.
- Los datos reales nunca entran al repo: viven en el caché o en `salidas/`,
  que git ignora.
