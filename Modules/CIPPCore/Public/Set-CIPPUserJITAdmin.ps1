function Set-CIPPUserJITAdmin {
    [CmdletBinding()]
    Param(
        [string]$TenantFilter,
        [string]$UserId,
        [switch]$Enabled,
        $Expiration
    )
    $Schema = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/schemaExtensions?`$filter=owner eq '$($env:applicationid)'" -NoAuthCheck $true -AsApp $true | Where-Object { $_.owner -eq $env:applicationid }

    $Body = [PSCustomObject]@{
        "$($Schema.id)" = @{
            jitAdminEnabled    = $Enabled.IsPresent
            jitAdminExpiration = $Expiration
        }
    }
    $Json = ConvertTo-Json -Depth 5 -InputObject $Body
    Write-Host $Json
    New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/beta/users/$UserId" -Body $Json -tenantid $TenantFilter
}