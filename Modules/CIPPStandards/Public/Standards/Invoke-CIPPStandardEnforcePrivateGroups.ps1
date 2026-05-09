function Invoke-CIPPStandardEnforcePrivateGroups {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnforcePrivateGroups
    .SYNOPSIS
        (Label) Enforce Private M365 Groups
    .DESCRIPTION
        (Helptext) Sets all public Microsoft 365 groups to private automatically. Groups can be excluded by display name keyword.
        (DocsDescription) Ensures only organisation-managed or approved public groups exist by automatically switching public Microsoft 365 (Unified) groups to private visibility. Groups whose display name matches any of the configured exclusion keywords are left unchanged. This aligns with CIS M365 6.0.1 benchmark control 1.2.1.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 6.0.1 (1.2.1)"
        EXECUTIVETEXT
            Enforces private visibility on all Microsoft 365 groups to prevent unauthorised external access to group resources such as Teams, SharePoint sites, and Planner boards. Approved public groups can be excluded by name, ensuring governance while retaining flexibility for intentionally public collaboration spaces.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"standards.EnforcePrivateGroups.ExcludedGroupNames","label":"Exclude groups by display name keyword","multiple":true,"creatable":true,"required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-06
        POWERSHELLEQUIVALENT
            Update-MgGroup -GroupId <id> -Visibility Private
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVE_BASIC"
            "ONEDRIVE_ENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'EnforcePrivateGroups' -TenantFilter $Tenant `
        -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'SHAREPOINTENTERPRISE_GOV', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
    if ($TestResult -eq $false) { return $true }

    # Parse exclusion keywords from settings
    $ExcludeKeywords = @(
        @($Settings.ExcludedGroupNames) | ForEach-Object {
            if ($_ -is [string]) { $_ } else { [string]($_.value ?? $_.label) }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    # Get all M365 (Unified) groups
    try {
        $AllGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=groupTypes/any(c:c eq 'Unified')&`$select=id,displayName,visibility&`$top=999" -tenantid $Tenant)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "EnforcePrivateGroups: Could not retrieve groups. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # Identify public groups, excluding any that match exclusion keywords
    $PublicGroups = foreach ($Group in $AllGroups) {
        if ($Group.visibility -ne 'Public') { continue }
        $IsExcluded = $false
        foreach ($Keyword in $ExcludeKeywords) {
            if ($Group.displayName -match [regex]::Escape($Keyword)) {
                $IsExcluded = $true
                break
            }
        }
        if (-not $IsExcluded) { $Group }
    }

    $StateIsCorrect = ($PublicGroups.Count -eq 0)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All M365 groups are already private (or excluded).' -sev Info
        } else {
            $SuccessCount = 0
            $FailCount = 0
            foreach ($Group in $PublicGroups) {
                try {
                    $Body = @{ visibility = 'Private' } | ConvertTo-Json -Compress -Depth 10
                    New-GraphPostRequest -tenantid $Tenant -Uri "https://graph.microsoft.com/beta/groups/$($Group.id)" `
                        -Type PATCH -Body $Body -ContentType 'application/json'
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set group '$($Group.displayName)' to Private." -sev Info
                    $SuccessCount++
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set group '$($Group.displayName)' to Private: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    $FailCount++
                }
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "EnforcePrivateGroups: Remediated $SuccessCount group(s), $FailCount failure(s)." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All M365 groups are private (or excluded).' -sev Info
        } else {
            $GroupNames = ($PublicGroups | Select-Object -ExpandProperty displayName) -join ', '
            Write-StandardsAlert -message "The following M365 groups are public and not excluded: $GroupNames" `
                -object ($PublicGroups | Select-Object id, displayName, visibility) `
                -tenant $Tenant -standardName 'EnforcePrivateGroups' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            PublicGroupCount = @($PublicGroups).Count
            PublicGroups     = ($PublicGroups | Select-Object -ExpandProperty displayName) -join ', '
        }
        $ExpectedValue = [PSCustomObject]@{
            PublicGroupCount = 0
            PublicGroups     = ''
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.EnforcePrivateGroups' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EnforcePrivateGroups' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
