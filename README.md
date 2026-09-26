# KnowIT.AzureCosts

Módulo de PowerShell que genera un Excel con el costo mensual de una
suscripción de Azure y, sobre todo, **qué recursos están sin etiquetar y
cuánto gastan**. Está pensado para personal financiero y directivo.

Usa la Cost Details API de Cost Management y Azure Resource Graph. **Solo lee:
no crea ni modifica nada en Azure.**

> **Los montos pueden no cuadrar contra la factura.** Son el costo de consumo
> que reporta Cost Management y, según el tipo de contrato, no incluyen
> descuentos, créditos, impuestos ni ajustes. En suscripciones CSP salen a
> precio retail de pay-as-you-go, sin los descuentos del partner. Sirven para
> ver proporciones, tendencias y cuánto gasta cada etiqueta. El Excel lo
> advierte en la portada.

## Requisitos

- **PowerShell 7.4 o superior** (`pwsh`). Windows PowerShell 5.1 no está
  soportado.
- Los módulos **Az.Accounts** e **ImportExcel 7.x**:
  ```powershell
  Install-PSResource Az.Accounts
  Install-PSResource ImportExcel -Version '[7.8,8.0)'
  ```
  ImportExcel 7.x trae EPPlus 4.5 (LGPL). EPPlus 5 y posteriores piden
  licencia comercial, así que el módulo se niega a cargar si ImportExcel trae
  EPPlus 5 o mayor.

**Permisos en Azure**, sobre la suscripción:

| Rol | Para qué |
|---|---|
| **Cost Management Reader** (o Contributor) | `Get-CostDetail`: leer los costos |
| **Reader** | `Get-ResourceInventory`: leer los recursos. Cost Management Reader no alcanza para esto |

Los dos son de solo lectura. Para asignarlos se necesita Owner o User Access
Administrator en la suscripción, y el permiso puede tardar hasta 30 minutos en
aplicarse.

- **Suscripciones CSP:** el partner tiene que activar la política de **cost
  visibility** para el cliente en Cost Management. Sin ella, la API de costos
  responde 403.
- **Acceso delegado con Azure Lighthouse:** basta con iniciar sesión en el
  tenant que administra. El token de ese tenant sirve para las suscripciones
  delegadas, siempre que la delegación incluya los roles de arriba.
- La Cost Details API funciona con suscripciones de Enterprise Agreement y
  Microsoft Customer Agreement (incluye CSP). Pay-as-you-go no está
  soportado.

## Instalación

Cuando el módulo esté publicado en PSGallery:

```powershell
Install-PSResource KnowIT.AzureCosts -Prerelease
Import-Module KnowIT.AzureCosts
```

Para usarlo desde el código fuente, ver [Desarrollo](#desarrollo).

## Generar un reporte

```powershell
Connect-AzAccount -Tenant <tenant>   # sin navegador: agrega -UseDeviceAuthentication
```

**1. Busca el ID de la suscripción:**

```powershell
Get-AzSubscription | Sort-Object Name | Format-Table Name, Id
```

**2. Descarga el detalle de costos del mes y el inventario de recursos:**

```powershell
$sub = '<id de la suscripción>'
$mes = '2026-08'

$csv = Get-CostDetail -SubscriptionId $sub -Month $mes -Path ./salidas -Verbose
$inv = Get-ResourceInventory -SubscriptionId $sub -OutFile ./salidas/inventario-$sub.json
```

`Get-CostDetail` tarda unos minutos: Azure genera el archivo y el módulo espera
a que termine. Guarda uno o varios CSV como
`detalle-<suscripción>-<mes>-partN.csv`. **Microsoft pide no consultar esta API
más de una vez al día por suscripción**, así que no la repitas: todo lo demás
se genera a partir de esos CSV.

`-OutFile` guarda el inventario para poder regenerar el Excel después sin
volver a Azure. El inventario refleja cómo están los recursos el día en que se
consulta, no el mes del reporte.

**3. Genera el Excel.** Indica qué tags debe tener un recurso para contar como
etiquetado:

```powershell
$csv | New-CostReport -Inventory $inv -RequiredTags Environment, Owner, CostCenter `
    -Path ./salidas/reporte-costos-$sub-$mes.xlsx
```

Los nombres de tag no distinguen mayúsculas (`CostCenter` y `costcenter`
cuentan igual), pero escríbelos como están en Azure: así aparecen en las
columnas del Excel y de la plantilla.

En pantalla sale el resumen: costo total, porcentaje sin etiquetar, cuántos
recursos sin etiquetar y la ruta del Excel.

### Qué trae el Excel

| Hoja | Contenido |
|---|---|
| Resumen | Totales del mes, % sin etiquetar y la advertencia sobre la factura |
| Diagnostico | Columnas detectadas y cifras de control para validar los datos |
| Sin etiquetar (con costo) | Lo que hay que corregir primero: recursos sin los tags requeridos que sí generaron costo |
| Costo por RG | Costo por resource group |
| Cobertura de tags | Qué tanto se usa cada tag |
| Costo por recurso | El detalle completo por recurso |
| Inventario sin etiquetar | Recursos que existen hoy sin los tags requeridos y que no generaron costo en el mes |
| Cargos sin recurso ARM | Cargos que no corresponden a un recurso vigente: Marketplace, reservas o recursos borrados |

### Regenerar sin volver a consultar Azure

Para cambiar los tags exigidos o rehacer el Excel, usa los archivos guardados.
Esto no llama a Azure, así que puedes repetirlo las veces que quieras:

```powershell
$inv = Get-ResourceInventory -Path ./salidas/inventario-$sub.json
Get-ChildItem ./salidas/detalle-$sub-$mes-part*.csv |
    New-CostReport -Inventory $inv -RequiredTags Environment, Owner `
        -Path ./salidas/reporte-costos-$sub-$mes.xlsx
```

### Plantilla de etiquetas pendientes

Genera un Excel con los recursos a los que les falta algún tag, con una columna
por tag para que alguien los llene a mano:

```powershell
Get-ChildItem ./salidas/detalle-$sub-$mes-part*.csv |
    New-TagTemplate -Inventory $inv -RequiredTags Environment, Owner, CostCenter `
        -Path ./salidas/etiquetas-pendientes-$sub.xlsx
```

Todavía no existe el paso que aplica en Azure los tags de la plantilla ya
llenada.

## Funciones

| Función | Qué hace | Llama a Azure |
|---|---|---|
| `Get-CostDetail` | Genera y descarga el detalle de un mes con la Cost Details API y guarda los CSV | Sí (≤1 consulta al día) |
| `Get-ResourceInventory` | Inventario de Resource Graph (lo guarda con `-OutFile`), o desde un JSON guardado (`-Path`) | Sí / No |
| `New-CostReport` | Arma el xlsx de costos y etiquetado desde los CSV | No |
| `New-TagTemplate` | Arma el xlsx de etiquetas pendientes | No |
| `Invoke-AzManagement` | Llamada genérica a Azure Resource Manager con objeto de respuesta | Sí |

## Límites de la Cost Details API

- Un mes por consulta, hasta 13 meses hacia atrás.
- Los datos de un mes recién cerrado tardan unos días en consolidarse.
- Solo trabaja por suscripción, no por resource group ni management group.

## Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| `No hay sesion de Azure` | Falta `Connect-AzAccount` |
| La suscripción no aparece en `Get-AzSubscription` | Tu cuenta no tiene acceso a ella, o iniciaste sesión en otro tenant |
| 403 en `Get-CostDetail` | Falta Cost Management Reader sobre la suscripción o, en CSP, la cost visibility del partner |
| Inventario vacío o incompleto | Falta el rol Reader sobre la suscripción |
| 429 en `Get-CostDetail` | Ya se consultó hoy esa suscripción. Usa los CSV guardados o espera al día siguiente |
| `no hay datos de costo` | El mes es muy reciente (espera unos días) o tiene más de 13 meses |
| `ImportExcel cargo EPPlus 5...` | Tienes una versión de ImportExcel con EPPlus comercial. Instala ImportExcel 7.x |
| `WARNING: ImportExcel Module Cannot Autosize` | Es normal: el módulo calcula los anchos de columna por su cuenta. Ignóralo |

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

Revisa las cifras del análisis sobre datos sintéticos. No necesita Azure.

```powershell
pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <id>
pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <id> -IncludeCostDetail -Month 2026-08
```

Prueba las llamadas reales con tu sesión de Az. Sin `-IncludeCostDetail` solo
lee la suscripción y el inventario. Con `-IncludeCostDetail` además descarga
el detalle de costos y arma el reporte, lo que gasta la consulta del día. Si
los CSV de ese mes ya están en `salidas/`, los reutiliza sin llamar a la API;
para forzar la descarga agrega `-Force`.

```
src/
  KnowIT.AzureCosts.psm1  Carga las funciones y valida la versión de EPPlus
  public/                 Funciones exportadas
  private/                Análisis, lectura de columnas, generación del Excel, tokens
tests/                    Verificar.ps1 (sin Azure) y Probar-Azure.ps1 (con Azure)
module.psd1               Definición del módulo para KnowIT.Builder
run.ps1                   Carga el módulo desde el código fuente
dev-build.ps1             Compila el módulo
salidas/                  Datos reales generados localmente. Ignorado por git
```
