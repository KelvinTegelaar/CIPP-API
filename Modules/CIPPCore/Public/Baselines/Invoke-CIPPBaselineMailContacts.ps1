function Invoke-CIPPBaselineMailContacts {
    <#
    .SYNOPSIS
        MailContacts executor: writes the configured organization contacts.
    .DESCRIPTION
        One app-only PATCH carrying only the members the baseline configures - the
        classic's write: marketing and technical addresses replace their lists, and the
        general contact lands on the privacy profile.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $OrgId = "$($Current.organizationId)"
    if ([string]::IsNullOrWhiteSpace($OrgId)) { return }

    $Body = [PSCustomObject]@{}
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.marketingContact)")) {
        $Body | Add-Member -NotePropertyName 'marketingNotificationEmails' -NotePropertyValue @("$($Remediate.marketingContact)")
    }
    $TechSet = @(@("$($Remediate.securityContact)", "$($Remediate.techContact)") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($TechSet.Count -gt 0) {
        $Body | Add-Member -NotePropertyName 'technicalNotificationMails' -NotePropertyValue @($TechSet)
    }
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.generalContact)")) {
        $Body | Add-Member -NotePropertyName 'privacyProfile' -NotePropertyValue @{ contactEmail = "$($Remediate.generalContact)" }
    }
    if (@($Body.PSObject.Properties).Count -eq 0) { return }

    $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/v1.0/organization/$OrgId" -type PATCH -body (ConvertTo-Json -InputObject $Body -Depth 5) -AsApp $true -ContentType 'application/json'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Updated the organization notification contacts.' -Sev 'Info'
}
