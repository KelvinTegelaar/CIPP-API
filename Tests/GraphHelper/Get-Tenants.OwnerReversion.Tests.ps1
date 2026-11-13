# Ownership of a customer tenant moves between partners inside Get-Tenants whenever the current
# owner drops off knownPartners - a manual pin reverting to auto, or an auto owner handing over
# because its relationship went away. Tokens are cached per customer tenant and carry the partner
# they were minted under, so the cache has to be dropped at the same moment the owner changes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-AzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Get-CIPPPartnerTenant { param($TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $Version) }
    function New-CIPPTenantRow { param($Item, $DefaultDomainName, $InitialDomainName, $RequiresRefresh) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $message, $Sev, $level, $LogData, $headers) }
    function Get-CippException { param($Exception) }
    function Get-CIPPFeatureFlag { param($Id) }
    function Clear-CippTokenCache { param($TenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-Tenants.ps1')

    $script:PrimaryPartner = '11111111-1111-1111-1111-111111111111'
    $script:PartnerB = '22222222-2222-2222-2222-222222222222'
    $script:CustomerId = '33333333-3333-3333-3333-333333333333'

    $script:OriginalTenantId = $env:TenantID
    $script:OriginalRefreshToken = $env:RefreshToken
    $env:TenantID = $script:PrimaryPartner
    $env:RefreshToken = 'refresh-token'
}

AfterAll {
    $env:TenantID = $script:OriginalTenantId
    $env:RefreshToken = $script:OriginalRefreshToken
}

Describe 'Get-Tenants owner changes' {
    BeforeEach {
        # Relationship set per partner - a partner missing from here has no active relationship.
        $script:RelationshipsByPartner = @{}

        Mock Get-CippTable { @{ Context = $tablename } }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Add-AzDataTableEntity {}
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
        Mock Start-CIPPOrchestrator {}
        Mock Clear-CippTokenCache { 1 }
        Mock Get-CIPPFeatureFlag { [PSCustomObject]@{ Id = $Id; Enabled = $true } }

        Mock Get-CIPPPartnerTenant {
            @(
                [PSCustomObject]@{ RowKey = $script:PrimaryPartner; Managed = $true }
                [PSCustomObject]@{ RowKey = $script:PartnerB; Managed = $true }
            )
        }

        Mock Get-CIPPAzDataTableEntity {
            if ($Context -eq 'tenantMode') { return [PSCustomObject]@{ state = 'default' } }
            if ($Filter -like '*Excluded eq true*') { return @() }
            if ($Context -eq 'Tenants') { return @($script:ExistingRow) }
            return @()
        }
        Mock Get-AzDataTableEntity { @() }

        Mock New-GraphGetRequest {
            $Relationships = $script:RelationshipsByPartner[$tenantid]
            if (-not $Relationships) { return @() }
            return @($Relationships)
        }
    }

    It 'clears the token cache when a manual pin reverts to automatic assignment' {
        $script:ExistingRow = [PSCustomObject]@{
            RowKey                = $script:CustomerId
            PartitionKey          = 'Tenants'
            customerId            = $script:CustomerId
            displayName           = 'Contoso'
            defaultDomainName     = 'contoso.onmicrosoft.com'
            initialDomainName     = 'contoso.onmicrosoft.com'
            partnerTenantId       = $script:PartnerB
            partnerAssignmentMode = 'manual'
            knownPartners         = "$($script:PrimaryPartner),$($script:PartnerB)"
            RequiresRefresh       = $false
            LastRefresh           = [DateTimeOffset]::UtcNow.AddDays(-1)
            GraphErrorCount       = 0
            Excluded              = $false
        }
        $script:RelationshipsByPartner[$script:PrimaryPartner] = @(
            [PSCustomObject]@{
                customer          = [PSCustomObject]@{ tenantId = $script:CustomerId; displayName = 'Contoso' }
                autoExtendDuration = 'PT0S'
                endDateTime        = '2026-12-01T00:00:00Z'
            }
        )

        $Result = Get-Tenants -TriggerRefresh -SkipDomains

        $Result.partnerTenantId | Should -Be $script:PrimaryPartner
        $Result.partnerAssignmentMode | Should -Be 'auto'
        Should -Invoke Clear-CippTokenCache -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq $script:CustomerId }
    }

    It 'clears the token cache when an automatic owner hands over to another partner' {
        $script:ExistingRow = [PSCustomObject]@{
            RowKey                = $script:CustomerId
            PartitionKey          = 'Tenants'
            customerId            = $script:CustomerId
            displayName           = 'Contoso'
            defaultDomainName     = 'contoso.onmicrosoft.com'
            initialDomainName     = 'contoso.onmicrosoft.com'
            partnerTenantId       = $script:PrimaryPartner
            partnerAssignmentMode = 'auto'
            knownPartners         = "$($script:PrimaryPartner)"
            RequiresRefresh       = $false
            LastRefresh           = [DateTimeOffset]::UtcNow.AddDays(-1)
            GraphErrorCount       = 0
            Excluded              = $false
        }
        $script:RelationshipsByPartner[$script:PartnerB] = @(
            [PSCustomObject]@{
                customer          = [PSCustomObject]@{ tenantId = $script:CustomerId; displayName = 'Contoso' }
                autoExtendDuration = 'PT0S'
                endDateTime        = '2026-12-01T00:00:00Z'
            }
        )

        $Result = Get-Tenants -TriggerRefresh -SkipDomains

        $Result.partnerTenantId | Should -Be $script:PartnerB
        Should -Invoke Clear-CippTokenCache -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq $script:CustomerId }
    }

    It 'leaves the token cache alone when the owner does not change' {
        $script:ExistingRow = [PSCustomObject]@{
            RowKey                = $script:CustomerId
            PartitionKey          = 'Tenants'
            customerId            = $script:CustomerId
            displayName           = 'Contoso'
            defaultDomainName     = 'contoso.onmicrosoft.com'
            initialDomainName     = 'contoso.onmicrosoft.com'
            partnerTenantId       = $script:PartnerB
            partnerAssignmentMode = 'manual'
            knownPartners         = "$($script:PrimaryPartner),$($script:PartnerB)"
            RequiresRefresh       = $false
            LastRefresh           = [DateTimeOffset]::UtcNow.AddDays(-1)
            GraphErrorCount       = 0
            Excluded              = $false
        }
        $Relationship = [PSCustomObject]@{
            customer          = [PSCustomObject]@{ tenantId = $script:CustomerId; displayName = 'Contoso' }
            autoExtendDuration = 'PT0S'
            endDateTime        = '2026-12-01T00:00:00Z'
        }
        $script:RelationshipsByPartner[$script:PrimaryPartner] = @($Relationship)
        $script:RelationshipsByPartner[$script:PartnerB] = @($Relationship)

        $Result = Get-Tenants -TriggerRefresh -SkipDomains

        $Result.partnerTenantId | Should -Be $script:PartnerB
        $Result.partnerAssignmentMode | Should -Be 'manual'
        Should -Invoke Clear-CippTokenCache -Times 0 -Exactly
    }
}
