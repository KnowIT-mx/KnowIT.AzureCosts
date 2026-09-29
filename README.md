# KnowIT.AzureCosts

Módulo de PowerShell para consultar y analizar costos de Azure por suscripción,
resource group, recurso y tag, desde la línea de comandos.

- **Devuelve objetos**, como cualquier comando de PowerShell.
- **Una sola dependencia:** `Az.Accounts`, para la sesión y los tokens.
- **Caché local:** la primera consulta de un mes descarga el detalle completo
  de la suscripción, y todo lo demás (filtros, otros tags, otros resource
  groups)
- **Solo lee:** no crea ni modifica nada en Azure.

> **Los montos pueden no cuadrar contra la factura.** Son el costo de consumo
> que reporta Cost Management y, según el tipo de contrato, no incluyen
> descuentos, créditos, impuestos ni ajustes. En suscripciones CSP salen a
> precio retail de pay-as-you-go, sin los descuentos finales del partner.

## Requisitos

- **PowerShell 7.4 o superior** (`pwsh`). Windows PowerShell 5.1 no está
  soportado.
- **Az.Accounts:** `Install-PSResource Az.Accounts`

**Permisos en Azure**, sobre la suscripción:

| Rol | Para qué |
|---|---|
| **Cost Management Reader** (o Contributor) | Detalle de costos (`Get-KnowITAzCostsDetail`, `Export-KnowITAzCostsRaw`) |
| **Reader** | Inventario de recursos, que también usa `Get-KnowITAzCostsDetail` para los tags de hoy. El rol de Cost Management Reader no es suficiente para obtener esta información |

Los dos son de solo lectura. Para asignarlos se necesita Owner o User Access
Administrator en la suscripción, y el permiso puede tardar hasta 30 minutos en
aplicarse.

- **Suscripciones CSP:** el partner tiene que activar la política de **cost
  visibility** para el cliente. Sin ella, la API de costos responde 403.
- **Acceso delegado con Azure Lighthouse:** basta con iniciar sesión en el
  tenant que administra; el token sirve para las suscripciones delegadas,
  siempre que la delegación incluya los roles de arriba.
- La Cost Details API funciona con suscripciones Enterprise Agreement y
  Microsoft Customer Agreement (incluye CSP). Pay-as-you-go no está soportado.

## Instalación

Cuando el módulo esté publicado en PSGallery:

```powershell
Install-PSResource KnowIT.AzureCosts -Prerelease
Import-Module KnowIT.AzureCosts
Connect-AzAccount -Tenant <tenant>   # sin navegador: agrega -UseDeviceAuthentication
```

Para usarlo desde el código fuente, ver [Desarrollo](#desarrollo).

## Comandos

| Comando | Qué devuelve |
|---|---|
| `Get-KnowITAzCostsResourceInventory` | Un objeto por recurso de Azure, con sus tags de hoy |
| `Get-KnowITAzCostsDetail` | Un objeto por recurso por mes, con el costo acumulado del periodo |
| `Export-KnowITAzCostsRaw` | Un CSV con el detalle diario por recurso tal como lo entrega la API, con los tags en columnas |
| `Clear-KnowITAzCostsCache` | Borra el caché local |

La referencia completa de cada comando está en [docs/](docs/README.md), al estilo de
Microsoft Learn. En la consola: `Get-Help Get-KnowITAzCostsDetail -Full`.

### Inventario de recursos

```powershell
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -ResourceGroup 'rg-prod-*'
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -Untagged      # sin ningún tag
Get-KnowITAzCostsResourceInventory                                     # todas las suscripciones accesibles
Get-AzSubscription | Get-KnowITAzCostsResourceInventory | ConvertTo-Json -Depth 4
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -Untagged -TagsAsJson | Export-Csv sin-tags.csv
```

Incluye los recursos que no generan cargo (un NSG, un disco desasociado), que
no aparecen en el detalle de costos. `-ResourceGroup` y `-Untagged` son
excluyentes.

### Costo por recurso

```powershell
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub
Get-KnowITAzCostsDetail -Period 2026-07, 2026-08 -SubscriptionId $sub
Get-KnowITAzCostsDetail -StartDate 2026-07-15 -EndDate 2026-08-14 -SubscriptionId $sub
```

Cada objeto trae `Month`, `SubscriptionId`, `ResourceId`, `ResourceName`,
`ResourceType`, `ResourceGroup`, `Location`, `ServiceName`, `Cost`, `Currency`,
`ExistsInInventory` y `Tags`. Con varios meses sale una fila por recurso por
mes; con un rango de fechas, los meses que el rango cubre a medias solo suman
los días dentro del rango.

- **Recursos borrados:** siguen saliendo, con `ExistsInInventory = $false`.
- **Cargos sin recurso** (Marketplace, soporte, reservas): salen como filas sin
  `ResourceId`, con `ServiceName` y `ChargeType`.
- **Data Factory:** los pipelines y triggers se suman a su factory.

Filtros:

```powershell
# Solo recursos sin ningún tag
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Untagged

# Por resource group (acepta comodines)
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -ResourceGroup 'rg-prod-*'

# Por tags: se deben cumplir todos los pares; los valores aceptan comodines
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Tag @{ Environment = 'Prod*'; Role = 'Web' }
```

`-Untagged` no se combina con `-ResourceGroup` ni con `-Tag`.

### Exportar los tags

`Tags` es una hashtable, cómoda para filtrar (`$_.Tags['Owner']`). Pero
`Export-Csv` escribe una hashtable como `System.Collections.Hashtable`. Para
exportar, `Get-KnowITAzCostsResourceInventory` y `Get-KnowITAzCostsDetail`
tienen dos opciones, que se pueden combinar:

```powershell
# Tags como JSON en una sola columna: {"Environment":"Production","Owner":"pepe"}
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -TagsAsJson | Export-Csv costos.csv

# Algunos tags en su propia columna (solo Get-KnowITAzCostsDetail)
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -TagColumn Environment, Owner -TagsAsJson |
    Export-Csv costos.csv
```

Con `-TagsAsJson` un recurso sin tags queda como `{}`. Si un tag de
`-TagColumn` se llama igual que una propiedad (por ejemplo `Location`), la
columna se llama `tag_Location`.

Algunos análisis comunes, con comandos nativos:

```powershell
$costos = Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub

# Costo por resource group
$costos | Group-Object ResourceGroup |
    Select-Object Name, @{ n = 'Cost'; e = { ($_.Group | Measure-Object Cost -Sum).Sum } } |
    Sort-Object Cost -Descending

# Cuánto gasta lo que no tiene tag
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Untagged | Measure-Object Cost -Sum
```

### Detalle crudo

```powershell
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./costos-2026-08.csv
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./costos.csv -TagColumn Environment, Owner
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./costos.csv -TagsFromInventory
```

Escribe un solo CSV con todas las columnas originales de la API (una fila por
recurso, día y medidor) y una columna por tag. Sin `-TagColumn` agrega todos
los tags que aparecen en las filas exportadas; el recurso que no tiene un tag
lo deja vacío. Acepta los mismos periodos y filtros que
`Get-KnowITAzCostsDetail`, y varias suscripciones y meses en el mismo archivo.

### Qué tags usa cada comando

| Comando | Tags |
|---|---|
| `Get-KnowITAzCostsResourceInventory` | Los de hoy |
| `Get-KnowITAzCostsDetail` | Ver la tabla siguiente |
| `Export-KnowITAzCostsRaw` | Los que tenía el recurso el día del cargo. Con `-TagsFromInventory`, los de hoy para los recursos que siguen existiendo |

En `Get-KnowITAzCostsDetail`:

| Caso | Sin `-SplitByTagChange`: una fila por recurso | Con `-SplitByTagChange`: una fila por juego de tags |
|---|---|---|
| El recurso existe hoy con tags | Los tags de hoy | Los tags que tuvo cada día del periodo |
| El recurso existe hoy sin tags | Sin tags | Los tags que tuvo cada día del periodo |
| El recurso fue borrado | Los últimos tags con valor del periodo | Los tags que tuvo cada día del periodo |
| Días en que el detalle viene sin tags | No cuentan | Forman su propia fila, sin tags |
| Pipelines y triggers de Data Factory | Se suman a su factory | Llevan los tags que la factory tuvo ese día; si la factory no tiene cargos ese día, los suyos |

Con `-SplitByTagChange` cada fila trae además `FirstDate` y `LastDate`: el primer
y el último día con ese juego de tags. El costo total es el mismo en ambos modos.

Los nombres de tag no distinguen mayúsculas, como en Azure. Un tag con valor
vacío no cuenta como etiquetado.

**Autocompletado:** en la consola, `-TagColumn` y `-Tag` completan con Tab los
tags y valores que existen en la suscripción indicada. Para `-Tag` se ofrece el
par ya escrito como hashtable: `@{ Environment = 'Production' }`.

## Caché

El caché vive en `~/.Azure/KnowIT.AzureCosts`, junto a los archivos de Az, con
una carpeta por suscripción. Cada usuario mantiene el suyo.

| Dato | Vigencia |
|---|---|
| Detalle de un mes cerrado | Permanente, si se descargó al menos 5 días después del cierre |
| Detalle del mes en curso o recién cerrado | 24 horas |
| Inventario de recursos | Un archivo por día |

`-Force` vuelve a consultar Azure aunque el dato esté en caché.
`Clear-KnowITAzCostsCache` borra todo el caché, el de una suscripción
(`-SubscriptionId`) o solo el detalle de algunos meses (`-Month`).

**Microsoft pide no consultar la Cost Details API más de una vez al día por
suscripción.** No uses `-Force` ni borres el caché sin necesidad.

## Límites de la Cost Details API

- Hasta 13 meses hacia atrás.
- Los datos de un mes recién cerrado tardan unos días en consolidarse.
- Solo trabaja por suscripción, no por resource group ni management group: por
  eso siempre se descarga la suscripción completa y se filtra localmente.

## Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| `No hay sesion de Azure` | Falta `Connect-AzAccount` |
| La suscripción no aparece | Tu cuenta no tiene acceso a ella, o iniciaste sesión en otro tenant |
| 403 en el detalle de costos | Falta Cost Management Reader sobre la suscripción o, en CSP, la cost visibility del partner |
| Inventario vacío o incompleto | Falta el rol Reader sobre la suscripción |
| 429 en el detalle de costos | Ya se consultó hoy esa suscripción. Espera al día siguiente |
| `Azure no tiene datos de costo de <mes>` | El mes es muy reciente, tiene más de 13 meses o la suscripción no tuvo consumo |
| El autocompletado de tags no ofrece nada | Falta `-SubscriptionId` antes del parámetro, o no hay sesión de Azure para traer el inventario |

## Desarrollo

Requiere además **KnowIT.Builder**, que compila el módulo:

```powershell
Install-PSResource KnowIT.Builder -Prerelease
```

```powershell
. ./run.ps1            # carga el módulo desde src/, desde la raíz del repo
./dev-build.ps1        # compila el módulo en out/KnowIT.AzureCosts
```

Pruebas:

```powershell
pwsh ./tests/Verificar.ps1
```

Prueba los comandos con datos sintéticos sembrados en un caché temporal. No
necesita Azure.

```powershell
pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <id> -Month 2026-08
pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <id> -Month 2026-08 -IncludeCostDetail
```

Prueba las llamadas reales con tu sesión de Az. Si el mes no está en caché,
solo lo descarga con `-IncludeCostDetail`, porque gasta la consulta del día.

```
src/
  KnowIT.AzureCosts.psm1  Carga las funciones y define la ruta del caché
  public/                 Comandos exportados
  private/                Llamadas a ARM, caché, agregación, filtros, autocompletado
docs/                     Referencia de los comandos, al estilo de Microsoft Learn
tests/                    Verificar.ps1 (sin Azure) y Probar-Azure.ps1 (con Azure)
module.psd1               Definición del módulo para KnowIT.Builder
run.ps1                   Carga el módulo desde el código fuente
dev-build.ps1             Compila el módulo
```
