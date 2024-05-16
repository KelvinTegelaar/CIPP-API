function Get-CIPPAlertAppSecretExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )

    try {
        Write-Host "Checking app expire for $($TenantFilter)"
        $appList = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $TenantFilter
        $AlertData = foreach ($App in $applist) {
            Write-Host "checking $($App.displayName)"
            if ($App.passwordCredentials) {
                foreach ($Credential in $App.passwordCredentials) {
                    if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                        Write-Host ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                        @{ DisplayName = $App.displayName; Expires = $Credential.endDateTime }
                    }
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        } else {
            Write-Host "Skipping app expire for $($TenantFilter)"
        }
    } catch {
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check App registration expiry for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

