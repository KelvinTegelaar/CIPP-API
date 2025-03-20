function Invoke-CustomDataSync {
    param(
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName CustomDataMapping
    $CustomData = Get-CIPPAzDataTableEntity @Table

    $Mappings = $CustomData | ForEach-Object {
        $Mapping = $_.JSON | ConvertFrom-Json
        $Mapping
    }

    Write-Host ($Mappings | ConvertTo-Json -Depth 10)
}
