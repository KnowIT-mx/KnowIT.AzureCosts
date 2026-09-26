function NewResourceItem ([string]$Id, [string]$Name, [string]$Type, [string]$ResourceGroup, [string]$Location, $Tags)
{
    $tabla = @{}
    if($Tags) {
        # Resource Graph entrega los tags como objeto; desde un JSON local, igual.
        foreach($p in $Tags.PSObject.Properties) {
            $tabla[[string]$p.Name] = [string]$p.Value
        }
    }
    [PSCustomObject]@{
        PSTypeName    = 'KnowIT.AzureCosts.Resource'
        Id            = $Id
        # El casing del ResourceId difiere entre el detalle de costos y ARG (ARG devuelve
        # /resourcegroups/ en minusculas). Normalizar es lo que hace posible el cruce.
        IdNorm        = $Id.ToLowerInvariant()
        Name          = $Name
        Type          = $Type
        ResourceGroup = $ResourceGroup
        Location      = $Location
        Tags          = $tabla
    }
}

# Sub-recursos que generan cargo con su propio ResourceId pero que Resource Graph no
# inventaria. Sin esto aparecen como "sin recurso ARM" aunque su padre exista. Lista
# explicita y no una regla generica de "subir al padre": una base SQL que no esta en ARG
# es una base borrada, y sumarla a su servidor la esconderia.
$script:SubrecursosAlPadre = [System.Collections.Generic.HashSet[string]]::new(
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

    $partes = $ResourceIdNorm.Substring($i + '/providers/'.Length).Split('/')
    if($partes.Count -lt 5) { return $null }
    if(!$script:SubrecursosAlPadre.Contains("$($partes[0])/$($partes[1])/$($partes[3])")) { return $null }

    return $ResourceIdNorm.Substring(0, $i) + "/providers/$($partes[0])/$($partes[1])/$($partes[2])"
}

function GetResourceGroupFromId ([string]$ResourceId)
{
    # /subscriptions/x/resourceGroups/MI-RG/providers/... -> MI-RG
    $partes = $ResourceId.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    for($i = 0; $i -lt $partes.Count - 1; $i++) {
        if($partes[$i] -eq 'resourcegroups') { return $partes[$i + 1] }
    }
    return ''
}

function TestTagValue ([hashtable]$Tags, [string]$Tag)
{
    # Un tag presente pero vacio no cuenta como etiquetado.
    ![string]::IsNullOrWhiteSpace($Tags[$Tag])
}
