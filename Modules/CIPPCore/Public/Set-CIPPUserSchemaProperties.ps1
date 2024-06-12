function Set-CIPPUserSchemaProperties {
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [string]$TenantFilter,
        [string]$UserId,
        [hashtable]$Properties
    )

    $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }

    $Body = [PSCustomObject]@{
        "$($Schema.id)" = $Properties
    }

    $Json = ConvertTo-Json -Depth 5 -InputObject $Body
    if ($PSCmdlet.ShouldProcess("User: $UserId", "Set Schema Properties to $($Properties|ConvertTo-Json -Compress)")) {
        New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/beta/users/$UserId" -Body $Json -tenantid $TenantFilter
    }
}