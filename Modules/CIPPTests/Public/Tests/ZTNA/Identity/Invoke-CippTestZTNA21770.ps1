function Invoke-CippTestZTNA21770 {
    <#
    .SYNOPSIS
    Inactive applications don't have highly privileged Microsoft Graph API permissions
    #>
    param($Tenant)

    $TestId = 'ZTNA21770'
    $Name = "Inactive applications don't have highly privileged Microsoft Graph API permissions"

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Entra ID P1, which the service principal sign-in activity report requires. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'Medium' -Name $Name -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        $ServicePrincipals = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'
        $SignInActivities = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipalSignInActivities'
        if (-not $ServicePrincipals -or -not $SignInActivities) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Service principals or service principal sign-in activity not found in database. Data collection may not have completed yet.' -Risk 'Medium' -Name $Name -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }
        $AppRoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'AppRoleAssignments'
        $Grants = Get-CIPPTestData -TenantFilter $Tenant -Type 'OAuth2PermissionGrants'
        $Catalog = Get-CIPPRiskyPermissionCatalog

        $SpById = @{}
        foreach ($Sp in $ServicePrincipals) { $SpById[[string]$Sp.id] = $Sp }
        $LastSignInByAppId = @{}
        foreach ($Activity in $SignInActivities) { $LastSignInByAppId[[string]$Activity.appId] = $Activity.lastSignInActivity.lastSignInDateTime }

        $Hits = [System.Collections.Generic.List[object]]::new()
        foreach ($Assignment in $AppRoleAssignments) {
            $Api = $Catalog.ApiByAppId[[string]$SpById[[string]$Assignment.resourceId].appId]
            $Entry = $null
            if ($Api -and $Catalog.Application.TryGetValue("$Api|$($Assignment.appRoleId)", [ref]$Entry)) {
                $Hits.Add(@([string]$Assignment.principalId, $Entry, 'Application'))
            }
        }
        foreach ($Grant in $Grants) {
            $Api = $Catalog.ApiByAppId[[string]$SpById[[string]$Grant.resourceId].appId]
            if (-not $Api) { continue }
            foreach ($Scope in ([string]$Grant.scope).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                $Entry = $null
                if ($Catalog.Delegated.TryGetValue("$Api|$Scope", [ref]$Entry)) { $Hits.Add(@([string]$Grant.clientId, $Entry, 'Delegated')) }
            }
        }

        $Privileged = @{}
        foreach ($Hit in $Hits) {
            $ClientId, $Entry, $Kind = $Hit
            if ($Entry.impact -notin 'High', 'Critical' -or -not $SpById.ContainsKey($ClientId)) { continue }
            $App = $Privileged[$ClientId]
            if (-not $App) {
                $App = [PSCustomObject]@{ Id = $ClientId; Risk = 'High'; Delegated = [System.Collections.Generic.SortedSet[string]]::new(); Application = [System.Collections.Generic.SortedSet[string]]::new() }
                $Privileged[$ClientId] = $App
            }
            if ($Entry.impact -eq 'Critical') { $App.Risk = 'Critical' }
            [void]$App.$Kind.Add([string]$Entry.name)
        }

        $Inactive = [System.Collections.Generic.List[object]]::new()
        $Active = [System.Collections.Generic.List[object]]::new()
        foreach ($App in $Privileged.Values) {
            $Sp = $SpById[$App.Id]
            $Row = [PSCustomObject]@{
                Id          = $App.Id
                AppId       = $Sp.appId
                DisplayName = $Sp.displayName
                Publisher   = $Sp.publisherName
                Risk        = $App.Risk
                Delegated   = @($App.Delegated) -join ', '
                Application = @($App.Application) -join ', '
                LastSignIn  = $LastSignInByAppId[[string]$Sp.appId]
            }
            if ($Row.LastSignIn) { $Active.Add($Row) } else { $Inactive.Add($Row) }
        }

        $Status = if ($Inactive.Count -eq 0) { 'Passed' } else { 'Failed' }
        $Result = [System.Text.StringBuilder]::new()
        if ($Status -eq 'Passed') {
            [void]$Result.Append("No inactive applications with high privileges`n")
        } else {
            [void]$Result.Append("Found $($Inactive.Count) inactive application(s) with high privileges`n")
        }

        if ($Privileged.Count -gt 0) {
            [void]$Result.Append("`n## Apps with privileged Graph permissions`n`n")
            [void]$Result.Append("| | Name | Risk | Delegated permission | Application permission | Publisher | Last sign in |`n")
            [void]$Result.Append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- |`n")
            $Shown = 0
            foreach ($Group in @(@{ Icon = '❌'; Rows = $Inactive }, @{ Icon = '✅'; Rows = $Active })) {
                foreach ($Row in $Group.Rows) {
                    if ($Shown -ge 50) { break }
                    $Shown++
                    $Link = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$($Row.Id)/appId/$($Row.AppId)"
                    $LastSignIn = if ($Row.LastSignIn) { $Row.LastSignIn } else { 'Never' }
                    [void]$Result.Append("| $($Group.Icon) | [$($Row.DisplayName)]($Link) | $($Row.Risk) | $($Row.Delegated) | $($Row.Application) | $($Row.Publisher) | $LastSignIn |`n")
                }
            }
            if ($Privileged.Count -gt $Shown) {
                [void]$Result.Append("`n... and $($Privileged.Count - $Shown) more application(s)`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'Medium' -Name $Name -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access control'
    }
}
