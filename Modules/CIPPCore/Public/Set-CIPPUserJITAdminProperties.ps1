function Set-CIPPUserJITAdminProperties {
    [CmdletBinding()]
    Param(
        [string]$TenantFilter,
        [string]$UserId,
        [switch]$Enabled,
        $Expiration,
        [switch]$Clear
    )

    $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }
    if ($Clear.IsPresent) {
        $Body = [PSCustomObject]@{
            "$($Schema.id)" = @{
                jitAdminEnabled    = $null
                jitAdminExpiration = $null
            }
        }
    } else {
        $Body = [PSCustomObject]@{
            "$($Schema.id)" = @{
                jitAdminEnabled    = $Enabled.IsPresent
                jitAdminExpiration = $Expiration.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
    }

    $Json = ConvertTo-Json -Depth 5 -InputObject $Body
    Write-Information $Json
    New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/beta/users/$UserId" -Body $Json -tenantid $TenantFilter | Out-Null
}