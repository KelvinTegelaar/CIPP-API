function Invoke-CIPPBaselineGroupTemplate {
    <#
    .SYNOPSIS
        GroupTemplate executor: creates the group or updates the existing one in place.
    .DESCRIPTION
        Create goes through New-CIPPGroup, the shared path that knows every group type. The
        update branches are the classic's, ported per type:

        Graph groups (Generic/Security/AzureRole/Dynamic/M365) PATCH description, and for
        Dynamic groups the membership rule (turning rule processing on with it). Exchange
        groups go through Set-DistributionGroup / Set-DynamicDistributionGroup for name,
        description, recipient filter and the RequireSenderAuthenticationEnabled flag, which
        is the INVERSE of the template's allowExternal and only enforced when the template
        expresses an opinion.

        Distribution types need an Exchange license; the check runs here exactly as the
        classic ran it, because the standard itself must stay available to tenants without
        Exchange deploying pure Graph groups.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Template = $Current.templateBody
    if (-not $Template) { return }
    $Existing = $Current.existingGroup

    $NormalizedGroupType = switch -Wildcard ("$($Template.groupType)".ToLower()) {
        '*dynamicdistribution*' { 'DynamicDistribution'; break }
        '*dynamic*' { 'Dynamic'; break }
        '*generic*' { 'Generic'; break }
        '*security*' { 'Security'; break }
        '*azurerole*' { 'AzureRole'; break }
        '*m365*' { 'M365'; break }
        '*unified*' { 'M365'; break }
        '*microsoft*' { 'M365'; break }
        '*distribution*' { 'Distribution'; break }
        '*mail*' { 'Distribution'; break }
        default { "$($Template.groupType)" }
    }

    if (-not $Existing) {
        if ($NormalizedGroupType -in @('Distribution', 'DynamicDistribution')) {
            $LicenseCheck = Test-CIPPStandardLicense -StandardName 'GroupTemplate' -TenantFilter $TenantFilter -Preset Exchange -SkipLog
            if ($LicenseCheck -eq $false) {
                throw "Cannot create group '$($Template.displayName)': the tenant is not licensed for Exchange."
            }
        }
        $Result = New-CIPPGroup -GroupObject $Template -TenantFilter $TenantFilter -APIName 'Baselines'
        if ($Result.Success -ne $true) {
            throw "Failed to create group '$($Template.displayName)': $($Result.Message)"
        }
        return
    }

    if ($NormalizedGroupType -in @('Generic', 'Security', 'AzureRole', 'Dynamic', 'M365')) {
        $PatchBody = [PSCustomObject]@{}
        if ("$($Existing.description)" -ne "$($Template.description)") {
            $PatchBody | Add-Member -NotePropertyName 'description' -NotePropertyValue $Template.description
        }
        if ($NormalizedGroupType -eq 'Dynamic' -and $Template.membershipRules -and "$($Existing.membershipRule)" -ne "$($Template.membershipRules)") {
            $PatchBody | Add-Member -NotePropertyName 'membershipRule' -NotePropertyValue $Template.membershipRules
            $PatchBody | Add-Member -NotePropertyName 'membershipRuleProcessingState' -NotePropertyValue 'On'
        }
        if (@($PatchBody.PSObject.Properties).Count -gt 0) {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($Existing.id)" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $PatchBody -Depth 10)
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated group '$($Template.displayName)'." -Sev 'Info'
        }
        return
    }

    $LicenseCheck = Test-CIPPStandardLicense -StandardName 'GroupTemplate' -TenantFilter $TenantFilter -Preset Exchange -SkipLog
    if ($LicenseCheck -eq $false) {
        throw "Cannot update group '$($Template.displayName)': the tenant is not licensed for Exchange."
    }

    if ($NormalizedGroupType -eq 'DynamicDistribution') {
        $SetParams = @{ Identity = $Existing.Identity }
        if ("$($Existing.RecipientFilter)" -notmatch [regex]::Escape("$($Template.membershipRules)")) {
            $SetParams.RecipientFilter = $Template.membershipRules
        }
        if ($SetParams.Count -gt 1) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DynamicDistributionGroup' -cmdParams $SetParams
        }
        if ($null -ne $Template.allowExternal) {
            $RequireAuth = [bool](-not $Template.allowExternal)
            if ([bool]$Existing.RequireSenderAuthenticationEnabled -ne $RequireAuth) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DynamicDistributionGroup' -cmdParams @{
                    Identity                           = "$($Existing.Name)"
                    RequireSenderAuthenticationEnabled = $RequireAuth
                }
            }
        }
    } else {
        $SetParams = @{ Identity = "$($Template.displayName)" }
        if ("$($Existing.description)" -ne "$($Template.description)") { $SetParams.Description = $Template.description }
        if ($null -ne $Template.allowExternal) {
            $RequireAuth = [bool](-not $Template.allowExternal)
            if ([bool]$Existing.RequireSenderAuthenticationEnabled -ne $RequireAuth) { $SetParams.RequireSenderAuthenticationEnabled = $RequireAuth }
        }
        if ($SetParams.Count -gt 1) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DistributionGroup' -cmdParams $SetParams
        }
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated Exchange group '$($Template.displayName)'." -Sev 'Info'
}
