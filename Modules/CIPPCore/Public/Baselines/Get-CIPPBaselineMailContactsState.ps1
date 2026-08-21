function Get-CIPPBaselineMailContactsState {
    <#
    .SYNOPSIS
        Prepare hook for MailContacts: the organization's notification contact addresses.
    .DESCRIPTION
        Grades only the contacts the baseline configures - an empty field expresses no
        opinion and must not strip a tenant's existing contact, the classic's own rule.
        Marketing grades as CONTAINS (the tenant list may carry others); technical grades
        the security+tech pair as a SET against technicalNotificationMails; general grades
        the privacy profile contact exactly.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Org = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Organization') | Select-Object -First 1
    if (-not $Org) { return @{ Current = $null } }

    $V = $Item.Variables
    $TechSet = @(@("$($V.SecurityContact)", "$($V.TechContact)") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique | Sort-Object)

    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}
    if (-not [string]::IsNullOrWhiteSpace("$($V.MarketingContact)")) {
        $Expected | Add-Member -NotePropertyName 'marketingContactPresent' -NotePropertyValue $true
        $Current | Add-Member -NotePropertyName 'marketingContactPresent' -NotePropertyValue ([bool](@($Org.marketingNotificationEmails) -contains "$($V.MarketingContact)"))
    }
    if ($TechSet.Count -gt 0) {
        $Expected | Add-Member -NotePropertyName 'technicalContacts' -NotePropertyValue @($TechSet)
        $Current | Add-Member -NotePropertyName 'technicalContacts' -NotePropertyValue @($Org.technicalNotificationMails | Sort-Object)
    }
    if (-not [string]::IsNullOrWhiteSpace("$($V.GeneralContact)")) {
        $Expected | Add-Member -NotePropertyName 'generalContact' -NotePropertyValue "$($V.GeneralContact)"
        $Current | Add-Member -NotePropertyName 'generalContact' -NotePropertyValue "$($Org.privacyProfile.contactEmail)"
    }
    if (@($Expected.PSObject.Properties).Count -eq 0) { return @{ Current = $null } }

    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'organizationId' -NotePropertyValue "$($Org.id)"

    @{ Expected = $Expected; Current = $Current }
}
