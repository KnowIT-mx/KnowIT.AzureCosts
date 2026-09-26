function FormatArmError ($Response)
{
    $detalle = "[$($Response.StatusCode)] $($Response.Error.code): $($Response.Error.message)"
    switch ($Response.StatusCode) {
        403 {
            "Azure respondio 403. Posibles causas:`n" +
            "  - La identidad no tiene Cost Management Reader (o Contributor) sobre la suscripcion`n" +
            "  - En suscripciones CSP: el partner no tiene activada la politica de cost visibility`n" +
            $detalle
        }
        429 {
            "Azure respondio 429 (rate limit). La Cost Details API esta pensada para consultas " +
            "poco frecuentes (Microsoft pide no mas de una al dia por suscripcion); reutiliza el " +
            "CSV ya descargado con New-CostReport -CostDetailPath.`n" + $detalle
        }
        default { $detalle }
    }
}
