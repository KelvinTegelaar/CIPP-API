function Get-CIPPStatsTenantSecurity {
    <#
    .SYNOPSIS
    Tenant capability counts and Conditional Access / Security Defaults posture counts for the anonymous stats payload

    .DESCRIPTION
    Capabilities come from the CacheCapabilities table that Get-CIPPTenantCapabilities maintains (one
    subscribedSkus snapshot per tenant). A tenant counts towards a capability when any of its enabled
    service plans is in that capability's plan list; the lists mirror the presets in
    Test-CIPPStandardLicense so the counts agree with what standards and tests gate on.

    Security posture buckets each tenant once:
      CALicensedWithPolicies              Entra P1/P2 and at least one cached CA policy
      CALicensedNoPolicies                Entra P1/P2 and an authoritative empty CA policy set
      NotLicensedSecurityDefaultsEnabled  no Entra P1/P2, Security Defaults on
      NotLicensedSecurityDefaultsDisabled no Entra P1/P2, Security Defaults off
      Unknown                             no capability snapshot, or no cached CA count / Security Defaults row to decide on

    .PARAMETER Tenants
    The Get-Tenants output already read by the caller; maps capability rows (keyed by domain or GUID) to the tenant's default domain

    .PARAMETER CACounts
    The ConditionalAccessPolicies-Count rows already read by the caller (PartitionKey = tenant domain, DataCount = policies)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Tenants,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$CACounts = @()
    )

    # Same plan lists as the presets in Test-CIPPStandardLicense
    $Presets = [ordered]@{
        Exchange             = @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')
        SharePoint           = @('SHAREPOINTWAC', 'SHAREPOINTWAC_EDU', 'SHAREPOINTSTANDARD', 'SHAREPOINTSTANDARD_EDU', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'SHAREPOINTENTERPRISE_GOV', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
        Intune               = @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
        Entra                = @('AAD_PREMIUM', 'AAD_PREMIUM_P2')
        EntraP2              = @('AAD_PREMIUM_P2')
        PIM                  = @('AAD_PREMIUM_P2', 'Entra_Identity_Governance')
        Teams                = @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')
        Compliance           = @('RMS_S_PREMIUM', 'RMS_S_PREMIUM2', 'MIP_S_CLP1', 'MIP_S_CLP2')
        DefenderForEndpoint  = @('MDE_SMB', 'WIN_DEF_ATP', 'DEFENDER_ENDPOINT_P1')
        DefenderForOffice365 = @('ATP_ENTERPRISE', 'ATP_ENTERPRISE_GOV', 'THREAT_INTELLIGENCE', 'THREAT_INTELLIGENCE_GOV')
    }

    $Capabilities = [ordered]@{}
    foreach ($Name in $Presets.Keys) { $Capabilities[$Name] = 0 }
    $Security = [ordered]@{
        CALicensedWithPolicies              = 0
        CALicensedNoPolicies                = 0
        NotLicensedSecurityDefaultsEnabled  = 0
        NotLicensedSecurityDefaultsDisabled = 0
        Unknown                             = 0
    }

    try {
        # Capability rows are keyed by whatever the caller passed as TenantFilter: a default domain or a customer GUID
        $DomainByKey = @{}
        foreach ($Tenant in $Tenants) {
            if ([string]::IsNullOrWhiteSpace($Tenant.defaultDomainName)) { continue }
            $DomainByKey[[string]$Tenant.defaultDomainName] = [string]$Tenant.defaultDomainName
            if ($Tenant.customerId) { $DomainByKey[[string]$Tenant.customerId] = [string]$Tenant.defaultDomainName }
        }

        # Enabled service plans per tenant domain; a tenant cached under both keys merges into one set
        $PlansByDomain = @{}
        $CapabilityTable = Get-CIPPTable -TableName 'CacheCapabilities'
        foreach ($Row in @(Get-CIPPAzDataTableEntity @CapabilityTable -Filter "PartitionKey eq 'Capabilities'" -Property RowKey, JSON)) {
            $Domain = $DomainByKey[[string]$Row.RowKey]
            if (-not $Domain -or [string]::IsNullOrWhiteSpace($Row.JSON)) { continue }
            $Org = try { [CIPP.CippJson]::ConvertFromJson([string]$Row.JSON, [string[]]@('servicePlans')) } catch { $null }
            if (-not $PlansByDomain.ContainsKey($Domain)) {
                $PlansByDomain[$Domain] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
            foreach ($Sku in @($Org)) {
                foreach ($Plan in @($Sku.servicePlans)) {
                    if ($Plan.servicePlanName -and $Plan.provisioningStatus -ne 'disabled') { [void]$PlansByDomain[$Domain].Add([string]$Plan.servicePlanName) }
                }
            }
        }

        foreach ($Domain in $PlansByDomain.Keys) {
            foreach ($Name in $Presets.Keys) {
                foreach ($Plan in $Presets[$Name]) {
                    if ($PlansByDomain[$Domain].Contains($Plan)) { $Capabilities[$Name]++; break }
                }
            }
        }

        $CACountByDomain = @{}
        foreach ($Row in $CACounts) {
            if ($Row.RowKey -ne 'ConditionalAccessPolicies-Count' -or -not $Row.PartitionKey) { continue }
            $CACountByDomain[[string]$Row.PartitionKey] = [int]$Row.DataCount
        }

        $SecurityDefaultsByDomain = @{}
        $SecurityDefaultRows = Get-CIPPDbItem -TenantFilter allTenants -Type 'SecurityDefaults' -ByTenant
        foreach ($Domain in $SecurityDefaultRows.Keys) {
            foreach ($Row in $SecurityDefaultRows[$Domain]) {
                if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
                $Policy = try { [CIPP.CippJson]::ConvertFromJson([string]$Row.Data, [string[]]@('isEnabled')) } catch { $null }
                foreach ($Item in @($Policy)) {
                    if ($null -ne $Item.isEnabled) { $SecurityDefaultsByDomain[[string]$Domain] = [bool]$Item.isEnabled }
                }
            }
        }

        foreach ($Tenant in $Tenants) {
            $Domain = [string]$Tenant.defaultDomainName
            if ([string]::IsNullOrWhiteSpace($Domain)) { continue }
            if (-not $PlansByDomain.ContainsKey($Domain)) { $Security.Unknown++; continue }

            $CALicensed = $false
            foreach ($Plan in $Presets.Entra) {
                if ($PlansByDomain[$Domain].Contains($Plan)) { $CALicensed = $true; break }
            }

            if ($CALicensed) {
                if (-not $CACountByDomain.ContainsKey($Domain)) { $Security.Unknown++ }
                elseif ($CACountByDomain[$Domain] -gt 0) { $Security.CALicensedWithPolicies++ }
                else { $Security.CALicensedNoPolicies++ }
            } else {
                if (-not $SecurityDefaultsByDomain.ContainsKey($Domain)) { $Security.Unknown++ }
                elseif ($SecurityDefaultsByDomain[$Domain]) { $Security.NotLicensedSecurityDefaultsEnabled++ }
                else { $Security.NotLicensedSecurityDefaultsDisabled++ }
            }
        }

        [PSCustomObject]@{
            TenantCapabilities = $Capabilities
            SecuritySettings   = $Security
        }
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate tenant security stats: $($_.Exception.Message)" -sev Warning
        [PSCustomObject]@{ TenantCapabilities = $null; SecuritySettings = $null }
    }
}
