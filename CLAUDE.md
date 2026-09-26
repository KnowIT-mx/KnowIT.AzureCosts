# KnowIT.AzureCosts

Contexto para Claude Code. Este archivo se carga solo al abrir la carpeta.
Léelo completo antes de tocar nada: contiene decisiones ya tomadas con razones
que no son obvias en el código, y hechos verificados contra la documentación
de Microsoft que **no hay que volver a investigar**.

## Qué es

Módulo de PowerShell **standalone** que genera un .xlsx con el costo mensual de
una suscripción de Azure y, sobre todo, qué recursos están sin etiquetar y
cuánto gastan, para personal financiero. No es un dashboard. Se publicará en
PSGallery.

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

## Decisiones tomadas y por qué

**Cost Details API, no el export nativo.** Se genera a demanda, sin crear
storage ni exports en la suscripción.

**`Get-CostDetail` guarda los CSV y todo lo demás trabaja sobre ellos.** La
API está limitada (~1 consulta al día). Regenerar con otros tags o sacar la
plantilla no debe volver a consultarla. `Get-ResourceInventory -OutFile` hace
lo mismo con el inventario.

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
lista explícita (`SubrecursosAlPadre`), no una regla genérica: una base SQL
que no está en ARG es una base borrada y debe seguir visible como tal.

**La portada del Excel advierte que los montos pueden no cuadrar con la
factura.** Sin ese aviso, finanzas compara contra la factura y concluye que el
reporte está mal. El texto es genérico porque la diferencia depende del
contrato (en CSP: precio retail sin descuentos del partner) y el módulo no la
puede deducir del CSV. No quites el aviso.

**ImportExcel 7.x (EPPlus 4.5.3.x, LGPL).** EPPlus 5+ exige licencia comercial:
en un entregable para terceros es un problema legal. `KnowIT.Builder` no
soporta topes de versión en `ExternalModules` (escribe
`System.Collections.Hashtable` en `ExternalModuleDependencies`), así que el
`.psm1` revisa al cargar la versión de EPPlus y se detiene si es 5 o mayor.
Los anchos de columna se calculan a mano porque el autoajuste de EPPlus
necesita GDI+, que no hay en Linux ni en macOS sin `libgdiplus`.

**Orden ordinal (`SortOrdinal`) donde el orden importa.** `Sort-Object` usa
reglas de la cultura y ordena distinto según la máquina.

**`-ErrorVariable` no sirve para contar errores en las pruebas.** También junta
los que la función atrapa en su propio `try/catch`. Las pruebas cuentan los
`ErrorRecord` del stream (`2>&1`) con `-ErrorAction Continue` explícito:
`Update-CallerPreference` toma la preferencia del script, no de una función
auxiliar.

## Estado de verificación

| Componente | Estado |
|---|---|
| Análisis y Excel | Idénticos celda por celda a una implementación de referencia validada de forma independiente, sobre datos reales (agosto 2026) |
| `tests/Verificar.ps1` | 51 verificaciones sobre datos sintéticos, pasan |
| `tests/Probar-Azure.ps1` | Pasan contra una suscripción CSP real con acceso delegado: más de 1,400 recursos con paginación correcta; detalle de julio 2026 descargado de punta a punta (202, sondeo, manifiesto, CSV de 21 MB) y reporte generado |
| Compilado con `dev-build.ps1` | Importa por nombre, exporta 5 funciones, genera el reporte |

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
- ImportExcel 7.8.10 (la más reciente en PSGallery a septiembre 2026) trae
  EPPlus 4.5.3.2. `Install-PSResource -Version '[7.8,8.0)'` acepta rangos NuGet.

## Convenciones

- Los comentarios explican **por qué**, no qué.
- Nada de connection strings ni llaves: todo por la sesión de
  `Connect-AzAccount` (usuario o managed identity).
- Antes de sugerir un comando o parámetro de Azure, verifícalo. Por eso hay
  una sección de hechos verificados.
- Datos reales solo en `salidas/`, que git ignora.
