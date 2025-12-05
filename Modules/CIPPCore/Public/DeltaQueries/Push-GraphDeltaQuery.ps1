function Push-GraphDeltaQuery {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        $Item
    )

    $Item = $Item | Select-Object -ExcludeProperty FunctionName | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
    try {
        New-GraphDeltaQuery @Item
    } catch {
        Write-Error "Failed to create Delta Query: $(Get-NormalizedError -Message $_.Exception.message)"
        Write-Warning $_.InvocationInfo.PositionMessage
    }

}