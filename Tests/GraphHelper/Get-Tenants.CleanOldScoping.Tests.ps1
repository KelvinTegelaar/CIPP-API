# Pester tests for Get-Tenants -CleanOld
#
# CleanOld deletes Tenants rows, so its scoping has to hold under every partial failure:
# a partner may only delete rows it owns, and only when its own relationship list was
# fetched successfully this run. Direct tenants and partner tenant rows are never deletable.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-Tenants.ps1'
    if (-not (Test-Path -LiteralPath $FunctionPath)) { throw "Could not locate $FunctionPath" }

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CippTable { param($tablename, $Context) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter) }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Get-CIPPPartnerTenant { param($PartnerTenantId, [switch]$IncludeDisabled) }
    function Get-CIPPFeatureFlag { param($Id) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $Version) }
    function New-CIPPTenantRow { param($Item, $DefaultDomainName, $InitialDomainName, $RequiresRefresh) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $message, $Sev, $level, $LogData, $headers, $tenant) }
    function Get-CippException { param($Exception) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Get-CIPPAuthentication { }

    . $FunctionPath

    $script:PrimaryPartner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:PartnerB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $script:CustomerA = '11111111-1111-1111-1111-111111111111'
    $script:CustomerB = '22222222-2222-2222-2222-222222222222'
    $script:CustomerStale = '33333333-3333-3333-3333-333333333333'
    $script:CustomerDirect = '44444444-4444-4444-4444-444444444444'

    function New-TenantRowStub {
        param(
            [string]$CustomerId,
            [string]$PartnerTenantId = '',
            [string]$DelegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges',
            [bool]$IsPartnerTenantRow = $false
        )
        [pscustomobject]@{
            PartitionKey             = 'Tenants'
            RowKey                   = $CustomerId
            customerId               = $CustomerId
            displayName              = "Tenant $CustomerId"
            defaultDomainName        = "$CustomerId.onmicrosoft.com"
            partnerTenantId          = $PartnerTenantId
            delegatedPrivilegeStatus = $DelegatedPrivilegeStatus
            isPartnerTenantRow       = $IsPartnerTenantRow
            Excluded                 = $false
        }
    }

    function New-RelationshipStub {
        param([string]$CustomerId)
        [pscustomobject]@{
            customer          = [pscustomobject]@{ tenantId = $CustomerId; displayName = "Tenant $CustomerId" }
            autoExtendDuration = 'PT0S'
            endDateTime        = (Get-Date).AddDays(30).ToString('o')
        }
    }

    function New-PartnerStub {
        param([string]$TenantId, [bool]$IsPrimary)
        [pscustomobject]@{
            PartitionKey    = 'Partners'
            RowKey          = $TenantId
            partnerTenantId = $TenantId
            IsPrimary       = $IsPrimary
            Enabled         = $true
        }
    }
}

Describe 'Get-Tenants -CleanOld scoping' {
    BeforeEach {
        $script:OriginalTenantId = $env:TenantID
        $script:OriginalRefreshToken = $env:RefreshToken
        $env:TenantID = $script:PrimaryPartner
        $env:RefreshToken = 'stub-refresh-token'

        # Every row the simulated Tenants table holds for the run under test.
        $script:TableRows = [System.Collections.Generic.List[object]]::new()
        # Relationship lists keyed by partner tenant id; a missing key means the fetch throws.
        $script:RelationshipsByPartner = @{}
        $script:FailingPartners = [System.Collections.Generic.List[string]]::new()
        $script:EmptyPartners = [System.Collections.Generic.List[string]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        $script:CleanPartners = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { 'stub-exception' }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CIPPFeatureFlag -MockWith { [pscustomobject]@{ Id = $Id; Enabled = $true } }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Add-AzDataTableEntity -MockWith { }
        Mock -CommandName Get-AzDataTableEntity -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { }

        Mock -CommandName Get-CIPPPartnerTenant -MockWith { @($script:CleanPartners) }

        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith {
            $script:Removed.Add($Entity)
        }

        # Honour the OData filters the function builds, so a filter regression shows up as
        # rows the clean pass should never have seen.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($TableName -eq 'tenantMode') {
                return [pscustomobject]@{ state = 'PartnerTenantAvailable' }
            }
            if ($Filter -like "*Excluded eq true*") {
                return @()
            }
            if ($Filter -like "*delegatedPrivilegeStatus ne 'directTenant'*") {
                return @($script:TableRows | Where-Object {
                        $_.Excluded -ne $true -and $_.delegatedPrivilegeStatus -ne 'directTenant'
                    })
            }
            # Any other read is the general tenant-cache read; a non-empty result keeps the
            # function out of the rebuild branch so the test exercises CleanOld only.
            return @($script:TableRows)
        }

        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($script:FailingPartners -contains $tenantid) {
                throw "Simulated relationship fetch failure for $tenantid"
            }
            if ($script:EmptyPartners -contains $tenantid) {
                return $null
            }
            return @($script:RelationshipsByPartner[$tenantid])
        }
    }

    AfterEach {
        $env:TenantID = $script:OriginalTenantId
        $env:RefreshToken = $script:OriginalRefreshToken
    }

    Context 'Rows owned by another partner' {
        It 'never deletes rows owned by a partner that is not in this clean pass' {
            # Partner B is disabled, so Get-CIPPPartnerTenant does not return it and its
            # relationships are never fetched. Its rows must survive the primary's pass.
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerA))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerB -PartnerTenantId $script:PartnerB))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)

            $null = Get-Tenants -CleanOld

            $script:Removed.customerId | Should -Not -Contain $script:CustomerB
            $script:Removed.Count | Should -Be 0
        }

        It 'deletes only the stale row of each owner when several partners clean in one pass' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PartnerB -IsPrimary $false))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerA))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerB -PartnerTenantId $script:PartnerB))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerStale))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)
            $script:RelationshipsByPartner[$script:PartnerB] = @(New-RelationshipStub -CustomerId $script:CustomerB)

            $null = Get-Tenants -CleanOld

            @($script:Removed.customerId) | Should -Be @($script:CustomerStale)
        }
    }

    Context 'A partner whose relationship fetch failed this run' {
        It 'spares the failed partner rows when the fetch throws' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PartnerB -IsPrimary $false))
            $script:FailingPartners.Add($script:PartnerB)
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerB -PartnerTenantId $script:PartnerB))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerStale))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)

            $null = Get-Tenants -CleanOld

            $script:Removed.customerId | Should -Not -Contain $script:CustomerB
            @($script:Removed.customerId) | Should -Be @($script:CustomerStale)
        }

        It 'spares the failed partner rows when the fetch returns nothing' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PartnerB -IsPrimary $false))
            $script:EmptyPartners.Add($script:PartnerB)
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerB -PartnerTenantId $script:PartnerB))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)

            $null = Get-Tenants -CleanOld

            $script:Removed.Count | Should -Be 0
        }

        It 'throws instead of deleting anything when the only partner fails' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:FailingPartners.Add($script:PrimaryPartner)
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerStale))

            { Get-Tenants -CleanOld } | Should -Throw

            $script:Removed.Count | Should -Be 0
        }
    }

    Context 'Rows that are never deletable' {
        It 'never reads, and so never deletes, direct tenants' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerDirect -DelegatedPrivilegeStatus 'directTenant'))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerStale))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)

            $null = Get-Tenants -CleanOld

            $script:Removed.customerId | Should -Not -Contain $script:CustomerDirect
            @($script:Removed.customerId) | Should -Be @($script:CustomerStale)
        }

        It 'spares partner tenant rows even though no relationship names them' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PartnerB -IsPrimary $false))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:PartnerB -PartnerTenantId $script:PartnerB -IsPartnerTenantRow $true))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:PrimaryPartner -PartnerTenantId $script:PrimaryPartner -IsPartnerTenantRow $true))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)
            $script:RelationshipsByPartner[$script:PartnerB] = @(New-RelationshipStub -CustomerId $script:CustomerB)

            $null = Get-Tenants -CleanOld

            $script:Removed.Count | Should -Be 0
        }
    }

    Context 'Rows genuinely gone from their owner list' {
        It 'deletes a row its own owner no longer has a relationship for' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerA))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerStale))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)

            $null = Get-Tenants -CleanOld

            @($script:Removed.customerId) | Should -Be @($script:CustomerStale)
        }

        It 'deletes an additional partner stale row during that partner pass' {
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PrimaryPartner -IsPrimary $true))
            $script:CleanPartners.Add((New-PartnerStub -TenantId $script:PartnerB -IsPrimary $false))
            $script:TableRows.Add((New-TenantRowStub -CustomerId $script:CustomerStale -PartnerTenantId $script:PartnerB))
            $script:RelationshipsByPartner[$script:PrimaryPartner] = @(New-RelationshipStub -CustomerId $script:CustomerA)
            $script:RelationshipsByPartner[$script:PartnerB] = @(New-RelationshipStub -CustomerId $script:CustomerB)

            $null = Get-Tenants -CleanOld

            @($script:Removed.customerId) | Should -Be @($script:CustomerStale)
        }
    }
}
