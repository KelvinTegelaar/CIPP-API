function Get-CIPPAlertNewServicePrincipalCredentials {
    <#
    .SYNOPSIS
        Alert on credentials recently added to service principals.
    .DESCRIPTION
        Lists every service principal (enterprise application) in the tenant and reports each
        client secret or certificate whose validity started within the look-back window. A
        credential added to a service principal grants whoever holds it the application's
        permissions in this tenant, so a new one on a multi-tenant app is a common sign of
        compromise and usually not something the vendor did on your behalf.
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

    $LookbackDays = 6
    # The form posts either the bare number or, for a multi-input layout, an object carrying it
    # under LookbackDays. Accept both and fall back to the default on anything unusable.
    $RawDays = if ($InputValue -is [System.Collections.IDictionary]) {
        $InputValue['LookbackDays']
    } elseif ($null -ne $InputValue -and $InputValue -isnot [string] -and $InputValue -isnot [ValueType] -and $InputValue.PSObject.Properties.Name -contains 'LookbackDays') {
        $InputValue.LookbackDays
    } else {
        $InputValue
    }
    $ParsedDays = 0
    if ($null -ne $RawDays -and [int]::TryParse([string]$RawDays, [ref]$ParsedDays) -and $ParsedDays -gt 0) {
        $LookbackDays = $ParsedDays
    }
    $Since = [datetime]::UtcNow.AddDays(-$LookbackDays)

    try {
        $ServicePrincipals = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,appId,displayName,appOwnerOrganizationId,accountEnabled,passwordCredentials,keyCredentials&`$top=999" -tenantid $TenantFilter)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "New service principal credentials alert: unable to list service principals: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $CredentialTypes = @(
        @{ Property = 'passwordCredentials'; Label = 'Secret' }
        @{ Property = 'keyCredentials'; Label = 'Certificate' }
    )
    $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($ServicePrincipal in $ServicePrincipals) {
        foreach ($Type in $CredentialTypes) {
            foreach ($Credential in @($ServicePrincipal.($Type.Property))) {
                if (-not $Credential.startDateTime) { continue }
                $StartUtc = ([datetime]$Credential.startDateTime).ToUniversalTime()
                if ($StartUtc -lt $Since) { continue }
                $Message = "A new {0} was added to service principal '{1}' on {2:u}." -f $Type.Label.ToLower(), $ServicePrincipal.displayName, $StartUtc
                $Finding = [PSCustomObject]@{
                    Message            = $Message
                    AppName            = $ServicePrincipal.displayName
                    AppId              = $ServicePrincipal.appId
                    ServicePrincipalId = $ServicePrincipal.id
                    AppOwnerTenantId   = $ServicePrincipal.appOwnerOrganizationId
                    Enabled            = $ServicePrincipal.accountEnabled
                    CredentialType     = $Type.Label
                    CredentialName     = $Credential.displayName
                    KeyId              = $Credential.keyId
                    StartDateTime      = $Credential.startDateTime
                    EndDateTime        = $Credential.endDateTime
                    LookbackDays       = $LookbackDays
                    Tenant             = $TenantFilter
                }
                $AlertData.Add($Finding)
            }
        }
    }

    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
