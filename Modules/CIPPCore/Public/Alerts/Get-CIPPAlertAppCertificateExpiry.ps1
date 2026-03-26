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

    $Now = Get-Date
    $AlertData = @()

    try {
        $appList = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Apps'
    } catch {
        $appList = @()
    }

    $AppAlertData = foreach ($App in $appList) {
        if ($App.keyCredentials) {
            foreach ($Credential in $App.keyCredentials) {
                if ($Credential.endDateTime -lt $Now.AddDays(30) -and $Credential.endDateTime -gt $Now.AddDays(-7)) {
                    @{
                        DisplayName = $App.displayName
                        Expires     = $Credential.endDateTime
                        AppId       = $App.appId
                        Type        = 'Application'
                    }
                }
            }
        }
    }

    try {
        $servicePrincipals = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals'
    } catch {
        $servicePrincipals = @()
    }

    $SamlAlertData = foreach ($ServicePrincipal in $servicePrincipals) {
        $ExpiryDate = $null
        if ($ServicePrincipal.preferredTokenSigningKeyEndDateTime) {
            $ExpiryDate = [datetime]$ServicePrincipal.preferredTokenSigningKeyEndDateTime
        }
        if ($ExpiryDate -and $ExpiryDate -lt $Now.AddDays(30) -and $ExpiryDate -gt $Now.AddDays(-7)) {
            @{
                DisplayName        = $ServicePrincipal.displayName
                Expires            = $ExpiryDate
                AppId              = $ServicePrincipal.appId
                ServicePrincipalId = $ServicePrincipal.id
                Type               = 'SamlServicePrincipal'
            }
        }
    }

    $AlertData = @(
        @($AppAlertData)
        @($SamlAlertData)
    ) | Where-Object { $null -ne $_ }
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
