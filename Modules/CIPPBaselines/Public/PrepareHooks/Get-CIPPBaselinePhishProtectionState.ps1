function Get-CIPPBaselinePhishProtectionState {
    <#
    .SYNOPSIS
        Prepare hook for PhishProtection: the phishing-check CSS on the sign-in branding.
    .DESCRIPTION
        Builds the tenant's expected canary CSS - the clone.cipp.app background-image URL
        carrying this instance's CIPPURL from the Config table, the classic's exact string -
        and grades whether the default branding localization's custom CSS contains it. The
        branding singleton reads live: it is one small object with no cache, exactly what
        the classic read. A tenant without premium branding reads as no CSS.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $TenantId = Get-Tenants -TenantFilter $TenantFilter
    $Table = Get-CIPPTable -TableName Config
    $CippConfig = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    $CIPPUrl = "$($CippConfig.Value)"

    $CurrentBody = $null
    try {
        $CurrentBody = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -tenantid $TenantFilter
    } catch {
        Write-Information "Baselines: could not read the branding CSS for $TenantFilter (tenant may lack premium branding): $($_.Exception.Message)"
    }

    $CSS = @"
.ext-sign-in-box {
    background-image: url(https://clone.cipp.app/api/PublicPhishingCheck?Tenantid=$($TenantFilter)&URL=https://$($CIPPUrl));
}
"@
    # The here-string inherits the source file's line endings, but the branding CSS round-trips
    # through Graph as LF. Normalise both sides so a CRLF checkout (or CSS stored with different
    # endings) still grades a re-read as a match rather than a silent drift.
    $CSS = $CSS -replace "`r`n", "`n"
    $NormalizedBody = "$CurrentBody" -replace "`r`n", "`n"

    $Current = [PSCustomObject]@{
        phishingCSSEnabled = [bool]($NormalizedBody -like "*$CSS*")
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'currentBody' -NotePropertyValue "$CurrentBody"
    $Current | Add-Member -NotePropertyName 'expectedCss' -NotePropertyValue $CSS
    $Current | Add-Member -NotePropertyName 'customerId' -NotePropertyValue "$($TenantId.customerId)"

    @{
        Expected = [PSCustomObject]@{ phishingCSSEnabled = $true }
        Current  = $Current
    }
}
