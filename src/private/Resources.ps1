function NewResourceItem ($Item)
{
    # $Item: fila de Resource Graph (id, name, type, resourceGroup, location, subscriptionId,
    # tags), recien consultada o leida del cache.
    $tags = @{}
    if($Item.tags) {
        foreach($property in $Item.tags.PSObject.Properties) {
            $tags[[string]$property.Name] = [string]$property.Value
        }
    }
    [PSCustomObject]@{
        PSTypeName     = 'KnowIT.AzureCosts.Resource'
        ResourceId     = $Item.id
        Name           = $Item.name
        Type           = $Item.type
        ResourceGroup  = $Item.resourceGroup
        Location       = $Item.location
        SubscriptionId = $Item.subscriptionId
        Tags           = $tags
    }
}

function NewInventoryIndex ([object[]]$Inventory)
{
    # El casing del ResourceId difiere entre el detalle de costos y ARG (ARG devuelve
    # /resourcegroups/ en minusculas). Indexar en minusculas es lo que hace posible el cruce.
    $index = @{}
    foreach($resource in $Inventory) {
        $index[$resource.ResourceId.ToLowerInvariant()] = $resource
    }
    $index
}

# Sub-recursos que generan cargo con su propio ResourceId pero que Resource Graph no
# inventaria. Sin esto aparecen como recursos inexistentes aunque su padre exista. Lista
# explicita y no una regla generica de "subir al padre": una base SQL que no esta en ARG
# es una base borrada, y sumarla a su servidor la esconderia.
$script:ChildToParentTypes = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'microsoft.datafactory/factories/pipelines'
        'microsoft.datafactory/factories/triggers'
    ),
    [StringComparer]::OrdinalIgnoreCase
)

function GetParentResourceId ([string]$ResourceIdNorm)
{
    # .../providers/microsoft.datafactory/factories/adf/pipelines/p1
    #   -> .../providers/microsoft.datafactory/factories/adf
    $i = $ResourceIdNorm.LastIndexOf('/providers/')
    if($i -lt 0) { return $null }

    $parts = $ResourceIdNorm.Substring($i + '/providers/'.Length).Split('/')
    if($parts.Count -lt 5) { return $null }
    if(!$script:ChildToParentTypes.Contains("$($parts[0])/$($parts[1])/$($parts[3])")) { return $null }

    return $ResourceIdNorm.Substring(0, $i) + "/providers/$($parts[0])/$($parts[1])/$($parts[2])"
}

function GetResourceGroupFromId ([string]$ResourceId)
{
    # /subscriptions/x/resourceGroups/MI-RG/providers/... -> MI-RG
    $parts = $ResourceId.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    for($i = 0; $i -lt $parts.Count - 1; $i++) {
        if($parts[$i] -eq 'resourcegroups') { return $parts[$i + 1] }
    }
    return ''
}

function TestUntagged ([hashtable]$Tags)
{
    # Un tag presente pero vacio no cuenta como etiquetado.
    foreach($value in $Tags.Values) {
        if(![string]::IsNullOrWhiteSpace($value)) { return $false }
    }
    return $true
}

function TestItemFilter
{
    # Filtros comunes a todos los comandos. -like: acepta comodines y no distingue
    # mayusculas, igual que Azure con nombres de resource group y de tag.
    param(
        [string]$ResourceGroup,
        [hashtable]$Tags,
        [string[]]$ResourceGroupFilter,
        [switch]$Untagged,
        [hashtable]$TagFilter
    )

    if($ResourceGroupFilter) {
        $match = $false
        foreach($pattern in $ResourceGroupFilter) {
            if($ResourceGroup -like $pattern) { $match = $true; break }
        }
        if(!$match) { return $false }
    }
    if($Untagged -and !(TestUntagged $Tags)) { return $false }
    if($TagFilter) {
        foreach($name in $TagFilter.Keys) {
            if(!$Tags.ContainsKey($name) -or $Tags[$name] -notlike $TagFilter[$name]) { return $false }
        }
    }
    return $true
}

function AssertFilterCombination ([hashtable]$BoundParameters)
{
    # -Untagged es "sin ningun tag": combinarlo con -Tag no puede devolver nada, y con
    # -ResourceGroup se decidio mantenerlos excluyentes.
    if($BoundParameters.ContainsKey('Untagged') -and $BoundParameters.Untagged) {
        foreach($name in 'ResourceGroup', 'Tag') {
            if($BoundParameters.ContainsKey($name)) {
                throw "-Untagged no se puede combinar con -$name."
            }
        }
    }
}

function AddTagColumns ([object[]]$Items, [string[]]$TagNames, [string[]]$ReservedNames, [string]$TagsProperty = 'Tags')
{
    # Una propiedad por tag, con el nombre del tag tal cual. Si choca con una propiedad
    # existente (p. ej. un tag 'Location') se le antepone tag_ solo a ese.
    $reserved = [System.Collections.Generic.HashSet[string]]::new([string[]]$ReservedNames, [StringComparer]::OrdinalIgnoreCase)
    $columns = @(foreach($tag in $TagNames) {
        @{ Tag = $tag; Column = $reserved.Contains($tag) ? "tag_$tag" : $tag }
    })
    foreach($item in $Items) {
        $tags = $item.$TagsProperty
        foreach($column in $columns) {
            $item | Add-Member -NotePropertyName $column.Column -NotePropertyValue ($tags[$column.Tag] ?? '') -Force
        }
    }
}

function GetTagNames ([object[]]$TagSets)
{
    # Nombres de tag sin repetir y sin distinguir mayusculas, en orden ordinal para que las
    # columnas salgan igual en cualquier maquina.
    $names = @{}
    foreach($tags in $TagSets) {
        foreach($key in $tags.Keys) {
            if(!$names.ContainsKey($key)) { $names[$key] = $key }
        }
    }
    @(SortOrdinal @($names.Values))
}

function ConvertTagsToJson ([object[]]$Items)
{
    # Export-Csv escribe una hashtable como 'System.Collections.Hashtable'. En JSON compacto
    # el CSV conserva los tags; las llaves en orden ordinal para que el texto sea el mismo en
    # cualquier maquina. Va al final: los filtros y -TagColumn necesitan la hashtable.
    foreach($item in $Items) {
        $ordered = [ordered]@{}
        foreach($key in (SortOrdinal @($item.Tags.Keys))) { $ordered[$key] = $item.Tags[$key] }
        $item.Tags = ConvertTo-Json -InputObject $ordered -Compress
    }
}
