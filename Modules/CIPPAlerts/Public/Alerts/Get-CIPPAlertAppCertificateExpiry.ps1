function Get-CIPPAlertAppCertificateExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $Now = Get-Date
    $AlertData = @()
    # A cache read that fails is 'could not check', not 'nothing expiring': skip the reconcile so open items stay open.
    $ReadFailed = $false

    try {
        $appList = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Apps'
    } catch {
        $appList = @()
        $ReadFailed = $true
    }

    $AppAlertData = foreach ($App in $appList) {
        if ($App.displayName -match 'ConnectSyncProvisioning') { continue }
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
        $ReadFailed = $true
    }

    $SamlAlertData = foreach ($ServicePrincipal in $servicePrincipals) {
        if ($ServicePrincipal.displayName -match 'ConnectSyncProvisioning') { continue }
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
    if ($ReadFailed) {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message 'App certificate expiry alert skipped: the application or service principal cache could not be read' -sev Info
        return
    }
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
