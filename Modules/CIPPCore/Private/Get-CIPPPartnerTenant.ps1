function Get-CIPPPartnerTenant {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Returns the partner (CSP) tenants configured for this instance.
    .DESCRIPTION
    The primary partner is $env:TenantID, seeded into the PartnerTenants table on first use.
    With the MultiPartner flag disabled only the primary is returned. Private on purpose.
    .PARAMETER PartnerTenantId
    Return only the partner with this tenant id (GUID).
    .PARAMETER IncludeDisabled
    Include partners marked Enabled = false.
    #>
    [CmdletBinding()]
    param(
        [string]$PartnerTenantId,
        [switch]$IncludeDisabled
    )

    # Load credentials if a caller runs before $env:TenantID is populated.
    if (!$env:TenantID) {
        $null = Get-CIPPAuthentication
    }
    if (!$env:TenantID) {
        throw 'TenantID is not configured. Cannot resolve partner tenants.'
    }

    $Primary = [PSCustomObject]@{
        PartitionKey    = 'Partners'
        RowKey          = "$env:TenantID"
        partnerTenantId = "$env:TenantID"
        displayName     = '*Partner Tenant'
        IsPrimary       = $true
        Enabled         = $true
    }

    $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
    if (-not $Flag.Enabled) {
        $Partners = @($Primary)
    } else {
        $Table = Get-CippTable -tablename 'PartnerTenants'
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Partners'"

        if (-not ($Rows | Where-Object { $_.RowKey -eq $env:TenantID })) {
            $Seed = @{
                PartitionKey    = 'Partners'
                RowKey          = "$env:TenantID"
                partnerTenantId = "$env:TenantID"
                displayName     = '*Partner Tenant'
                IsPrimary       = $true
                Enabled         = $true
                addedDate       = (Get-Date).ToUniversalTime()
            }
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Seed -Force
            $Rows = @($Rows) + @([PSCustomObject]$Seed)
        }

        # The primary is defined by the environment, never the table.
        $Partners = foreach ($Row in $Rows) {
            $Row | Add-Member -NotePropertyName IsPrimary -NotePropertyValue ($Row.RowKey -eq $env:TenantID) -Force -PassThru
        }
    }

    if (-not $IncludeDisabled.IsPresent) {
        $Partners = $Partners | Where-Object { $_.Enabled -ne $false }
    }
    if ($PartnerTenantId) {
        $Partners = $Partners | Where-Object { $_.RowKey -eq $PartnerTenantId }
    }

    return $Partners
}
