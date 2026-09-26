# Autocompletado de -Tag y -TagColumn a partir de los tags reales de la suscripcion. Sale
# del inventario del dia: si no esta en cache se consulta Resource Graph, que es barato y no
# tiene el limite de la Cost Details API. Cualquier error se calla: un autocompletado que
# falla no debe ensuciar la consola.

function GetCompletionTags ([hashtable]$BoundParameters)
{
    $subscriptions = @($BoundParameters.SubscriptionId | Where-Object { $_ })
    if(!$subscriptions) { return @() }
    try {
        $params = @{ SubscriptionId = $subscriptions; ErrorAction = 'Stop' }
        if($BoundParameters.Tenant) { $params.Tenant = $BoundParameters.Tenant }
        @((GetInventory @params).Tags)
    }
    catch {
        @()
    }
}

function NewQuotedWord ([string]$Text)
{
    $Text -match '^[\w.-]+$' ? $Text : "'$($Text -replace "'", "''")'"
}

function CompleteTagName ([hashtable]$BoundParameters, [string]$WordToComplete)
{
    $word = $WordToComplete.Trim("'", '"')
    foreach($name in (GetTagNames (GetCompletionTags $BoundParameters))) {
        if($name -like "$word*") {
            [System.Management.Automation.CompletionResult]::new((NewQuotedWord $name), $name, 'ParameterValue', $name)
        }
    }
}

function CompleteTagFilter ([hashtable]$BoundParameters, [string]$WordToComplete)
{
    # -Tag es un hashtable: se ofrece cada par tag=valor existente ya escrito como hashtable.
    # Lo escrito se compara contra el nombre o el valor.
    $word = $WordToComplete.Trim('@', '{', "'", '"', ' ')
    $pairs = @{}
    foreach($tags in (GetCompletionTags $BoundParameters)) {
        foreach($name in $tags.Keys) {
            $value = $tags[$name]
            if([string]::IsNullOrWhiteSpace($value)) { continue }
            $pairs["$name`0$value"] = @{ Name = $name; Value = $value }
        }
    }
    foreach($key in (SortOrdinal @($pairs.Keys))) {
        $pair = $pairs[$key]
        if($pair.Name -like "$word*" -or $pair.Value -like "$word*") {
            $text = "@{ $(NewQuotedWord $pair.Name) = '$($pair.Value -replace "'", "''")' }"
            [System.Management.Automation.CompletionResult]::new($text, "$($pair.Name)=$($pair.Value)", 'ParameterValue', $text)
        }
    }
}

# Se registran al cargar el modulo y no con [ArgumentCompleter()] en el parametro: en el
# modulo compilado el scriptblock del atributo no queda ligado al modulo y no ve las
# funciones privadas. Este si, porque se crea aqui dentro.
$script:TagCompletionCommands = 'Get-KnowITAzCostsDetail', 'Export-KnowITAzCostsRaw'
Register-ArgumentCompleter -CommandName $script:TagCompletionCommands -ParameterName TagColumn -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $boundParameters)
    CompleteTagName $boundParameters $wordToComplete
}
Register-ArgumentCompleter -CommandName $script:TagCompletionCommands -ParameterName Tag -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $boundParameters)
    CompleteTagFilter $boundParameters $wordToComplete
}
