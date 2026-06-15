function Enable-CIPPMDEConnector {
    <#
    .SYNOPSIS
        Provisions the Microsoft Defender for Endpoint Intune connector for a tenant.
    .DESCRIPTION
        Checks whether the MDE mobile threat defense connector (partnerState) is already 'available' or 'enabled'.
        If not, iterates through regional MDE API portal endpoints until one succeeds, then verifies
        the connector state afterwards. Endpoints are ordered so that the tenant's likely region
        (based on org countryLetterCode) is tried first.
    .PARAMETER TenantFilter
        The tenant domain or ID to provision the connector for.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # MDE connector ID is fixed across all tenants
    $ConnectorId = 'fc780465-2017-40d4-a0c5-307022471b92'
    $ConnectorUri = "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/$ConnectorId"

    # All known regional provisioning endpoints
    $AllEndpoints = @(
        'mde-rsp-apiportal-prd-eus.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-eus3.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-cus.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-cus3.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-weu.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-weu3.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-neu.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-neu3.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-uks.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-ukw.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-aue.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-aus.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-aec0a.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-aen0a.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-ins0a.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-inc0a.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-sww0a.securitycenter.windows.com'
        'mde-rsp-apiportal-prd-swn0a.securitycenter.windows.com'
    )

    # Country code -> likely regional endpoint prefixes (used to prioritize, not restrict)
    $RegionPriority = @{
        'US' = @('eus', 'eus3', 'cus', 'cus3')
        'CA' = @('eus', 'eus3', 'cus', 'cus3')
        'GB' = @('uks', 'ukw')
        'AU' = @('aue', 'aus', 'aec0a', 'aen0a')
        'IN' = @('ins0a', 'inc0a')
        'SE' = @('sww0a', 'swn0a')
        'DE' = @('weu', 'weu3')
        'FR' = @('weu', 'weu3')
        'NL' = @('weu', 'weu3')
        'BE' = @('weu', 'weu3')
        'AT' = @('weu', 'weu3')
        'CH' = @('weu', 'weu3')
        'IE' = @('neu', 'neu3')
        'FI' = @('neu', 'neu3')
        'NO' = @('neu', 'neu3')
        'DK' = @('neu', 'neu3')
    }

    # Check current connector state
    try {
        $ConnectorState = New-GraphGetRequest -uri $ConnectorUri -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'MDEConnector' -tenant $TenantFilter -message "Failed to retrieve MDE connector state. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        throw "Failed to retrieve MDE connector state for $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
    }

    if ($ConnectorState.partnerState -in @('available', 'enabled')) {
        Write-LogMessage -API 'MDEConnector' -tenant $TenantFilter -message 'MDE Intune connector is already in available state.' -Sev Info
        return [PSCustomObject]@{
            Success      = $true
            AlreadyDone  = $true
            PartnerState = $ConnectorState.partnerState
        }
    }

    # Build a prioritized endpoint list based on tenant country
    $PrioritizedEndpoints = [System.Collections.Generic.List[string]]::new()
    try {
        $OrgInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
        $CountryCode = $OrgInfo.countryLetterCode
        if ($CountryCode -and $RegionPriority.ContainsKey($CountryCode)) {
            $PrefixHints = $RegionPriority[$CountryCode]
            foreach ($endpoint in $AllEndpoints) {
                foreach ($prefix in $PrefixHints) {
                    if ($endpoint -like "*-prd-$prefix.*") {
                        $PrioritizedEndpoints.Add($endpoint)
                        break
                    }
                }
            }
        }
        Write-Information "MDE connector provisioning for $TenantFilter (country: $CountryCode): prioritized $($PrioritizedEndpoints.Count) regional endpoint(s)"
    } catch {
        Write-Information "Could not retrieve org country for $TenantFilter - will try all endpoints"
    }

    # Append remaining endpoints that weren't already prioritized
    foreach ($endpoint in $AllEndpoints) {
        if ($endpoint -notin $PrioritizedEndpoints) {
            $PrioritizedEndpoints.Add($endpoint)
        }
    }

    # Try each endpoint until one succeeds
    $ProvisionBody = '{"timeout":60000}'
    $ProvisionScope = 'https://api.securitycenter.windows.com/.default'
    $SuccessfulEndpoint = $null

    foreach ($endpoint in $PrioritizedEndpoints) {
        $ProvisionUri = "https://$endpoint/api/cloud/portal/onboarding/intune/provision"
        try {
            Write-Information "Attempting MDE provisioning for $TenantFilter via $endpoint"
            $null = New-GraphPOSTRequest -uri $ProvisionUri -tenantid $TenantFilter -body $ProvisionBody -scope $ProvisionScope
            $SuccessfulEndpoint = $endpoint
            Write-LogMessage -API 'MDEConnector' -tenant $TenantFilter -message "MDE Intune connector provisioned successfully via $endpoint" -Sev Info
            break
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Information "Endpoint $endpoint failed for $TenantFilter`: $($ErrorMessage.NormalizedError)"
        }
    }

    if (-not $SuccessfulEndpoint) {
        $Msg = "Failed to provision MDE Intune connector for $TenantFilter - all regional endpoints were unsuccessful."
        Write-LogMessage -API 'MDEConnector' -tenant $TenantFilter -message $Msg -Sev Error
        throw $Msg
    }

    # Verify the connector state after provisioning
    try {
        $UpdatedState = New-GraphGetRequest -uri $ConnectorUri -tenantid $TenantFilter
    } catch {
        $UpdatedState = $null
    }

    return [PSCustomObject]@{
        Success      = $UpdatedState.partnerState -in @('available', 'enabled')
        AlreadyDone  = $false
        Endpoint     = $SuccessfulEndpoint
        PartnerState = $UpdatedState.partnerState
    }
}
