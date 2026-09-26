**El objetivo de este modulo no es el que esta definido en el README.**

La intencion es desacoplar este modulo de cualquier aplicacion especifica 
y dejarlo como un modulo general de consulta y analisis de costos de Azure.
Con una minima dependecia a modulos o librerias externas, 
actualmente la unica aceptada seria Az.Account para descargar la autenticación, 
administracion delegada de suscripciones y manejo de tokens.

Pensemoslo como en una version "more curated and groomed" del modulo oficial de Microsoft Az.CostManagement.

Este modulo seria la base para aplicaciones y casos de uso mas específicas,  
como seria inicialmente la generación de un reporte financiero en Excel para uno o varios clientes, 
validacion y comparativo interno contra billing real del mayorista, 
generacion de datos consolidados por suscipcion o a nivel global como CSP.
Consultas on-demand por suscripcion, resource group, tag, etc directamente desde la linea de comandos.

Cada aplicacion o caso de uso podra tener su propio ownership y por lo tanto una UI/UX independiente
pudiendo ser utilizado de manera interactiva, mediante Automation, FuncionApps especificas o apps personalizadas
ya sea bajo nuestro dominio como KnowIT o en un Tenant/Suscripcion propia del cliente

Adicionalmente debera tener la capacidad de exportar los datos crudos o procesados ya sea a archivo, storage o alguna base de datos en particualr.

El desarrollo inicial se realiza en base a las necesidades de KnowIT, pero se debera considera que sera publicado en PowerShell Gallery
y pudiera llegar a ser utilizado por cualquier miembro de la comunidad, por lo que no debera mantener de manera interna o hard-coded ningun dato especifico de KnowIT, 
mas alla de los datos relacionados al ownership, development y maintenance del proyecto.


## Comandos principales

Los comandos deben seguir los estandares de PowerShell y generar objetos en su salida, 
con parametros o comandos auxiliares para exportar a otros formatos (Ej. Export-Csv, ConvertTo-Json, etc)

- Get-KnowITAzCostsResourceInventory (Suscripcion, [ResourceGroup | -Untagged])

- Get-KnowITAzCostsDetail (Filtros: Periodo, Suscripcion, ResourgeGroup, ColumnTags FilterTags, Filter[Abierto para queries mas especificos]) (ExportCsv)

- Export-KnowITAzCostsRaw (Este si es el mayor detalle proporcionado por el API (daily by resorce))


** Manejo de cache (anotado por pepe) **
