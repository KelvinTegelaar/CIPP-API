function Push-CIPPAlertAppSecretExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )

    try {
        Write-Host "Checking app expire for $($Item.tenant)"
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $Item.tenant | ForEach-Object {
            foreach ($App in $_) {
                Write-Host "checking $($App.displayName)"
                if ($App.passwordCredentials) {
                    foreach ($Credential in $App.passwordCredentials) {
                        if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                            Write-Host ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                            Write-AlertMessage -tenant $($Item.Tenant) -message ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                        }
                    }
                }
            }
        }
    } catch {
        #Write-AlertMessage -tenant $($Item.Tenant) -message "Failed to check App registration expiry for $($Item.Tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

