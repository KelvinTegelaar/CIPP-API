function Get-CIPPAlertAppCertificateExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        Write-Host "Checking app expire for $($TenantFilter)"
        $appList = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,keyCredentials" -tenantid $TenantFilter
    } catch {
        return
    }

    $AlertData = foreach ($App in $applist) {
        Write-Host "checking $($App.displayName)"
        if ($App.keyCredentials) {
            foreach ($Credential in $App.keyCredentials) {
                if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                    Write-Host ("Application '{0}' has certificates expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                    @{ DisplayName = $App.displayName; Expires = $Credential.endDateTime }
                }
            }
        }
    }
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
