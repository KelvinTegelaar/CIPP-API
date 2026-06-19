function Get-CIPPAlertIntunePolicyConflicts {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    # Normalize JSON/string input to object when possible
    if ($InputValue -is [string]) {
        try {
            if ($InputValue.Trim().StartsWith('{')) {
                $InputValue = $InputValue | ConvertFrom-Json -ErrorAction Stop
            }
        } catch {
            # Leave as-is if parsing fails
        }
    }

    $Config = [ordered]@{
        AlertEachIssue      = $false   # align with AlertEachAdmin convention (false = aggregated)
        IncludePolicies     = $true
        IncludeApplications = $true
        AlertConflicts      = $true
        AlertErrors         = $true
    }

    if ($InputValue -is [hashtable] -or $InputValue -is [pscustomobject]) {
        # Primary key follows AlertEach* convention; legacy Aggregate supported (true == aggregated)
        if ($null -ne $InputValue.AlertEachIssue) { $Config.AlertEachIssue = [bool]$InputValue.AlertEachIssue }
        if ($null -ne $InputValue.Aggregate) { $Config.AlertEachIssue = -not [bool]$InputValue.Aggregate }

        $Config.IncludePolicies = if ($null -ne $InputValue.IncludePolicies) { [bool]$InputValue.IncludePolicies } else { $Config.IncludePolicies }
        $Config.IncludeApplications = if ($null -ne $InputValue.IncludeApplications) { [bool]$InputValue.IncludeApplications } else { $Config.IncludeApplications }
        $Config.AlertConflicts = if ($null -ne $InputValue.AlertConflicts) { [bool]$InputValue.AlertConflicts } else { $Config.AlertConflicts }
        $Config.AlertErrors = if ($null -ne $InputValue.AlertErrors) { [bool]$InputValue.AlertErrors } else { $Config.AlertErrors }
    } elseif ($InputValue -is [bool]) {
        # Back-compat for boolean toggle used as Aggregate previously
        $Config.AlertEachIssue = -not [bool]$InputValue
    }

    if (-not $Config.IncludePolicies -and -not $Config.IncludeApplications) {
        return
    }

    $AlertableStatuses = @(
        if ($Config.AlertErrors) { 'error' }
        if ($Config.AlertConflicts) { 'conflict' }
    )

    if (-not $AlertableStatuses -and -not ($Config.IncludeApplications -and $Config.AlertErrors)) {
        return
    }

    $HasLicense = Test-CIPPStandardLicense -StandardName 'IntunePolicyStatus' -TenantFilter $TenantFilter -Preset Intune
    if (-not $HasLicense) {
        return
    }

    $Issues = [System.Collections.Generic.List[object]]::new()

    if ($Config.IncludePolicies -and $AlertableStatuses) {
        $PolicySources = @(
            @{ Type = 'IntuneDeviceCompliancePolicies'; Kind = 'Compliance' }
            @{ Type = 'IntuneDeviceConfigurations'; Kind = 'Configuration' }
        )

        foreach ($Source in $PolicySources) {
            try {
                $PolicyItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Source.Type | Where-Object { $_.RowKey -notlike '*-Count' }
                foreach ($PolicyItem in $PolicyItems) {
                    $Policy = try { $PolicyItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                    if (-not $Policy.id) { continue }

                    $StatusItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type "$($Source.Type)_$($Policy.id)" | Where-Object { $_.RowKey -notlike '*-Count' }
                    foreach ($StatusItem in $StatusItems) {
                        $State = try { $StatusItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                        if (-not $State.status -or ($AlertableStatuses -notcontains $State.status.ToLowerInvariant())) { continue }

                        $Issues.Add([PSCustomObject]@{
                                Message           = "$($Source.Kind) policy '$($Policy.displayName)' is $($State.status) on device '$($State.deviceDisplayName)' for $($State.userPrincipalName)."
                                Tenant            = $TenantFilter
                                Type              = 'Policy'
                                PolicyType        = $Source.Kind
                                PolicyName        = $Policy.displayName
                                IssueStatus       = $State.status
                                DeviceName        = $State.deviceDisplayName
                                UserPrincipalName = $State.userPrincipalName
                                DeviceId          = $State.id
                            })
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to read cached $($Source.Kind) policy states: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Config.IncludeApplications -and $Config.AlertErrors) {
        try {
            $AppItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppInstallStatusAggregate' | Where-Object { $_.RowKey -notlike '*-Count' }
            foreach ($AppItem in $AppItems) {
                $App = try { $AppItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                if (-not $App -or [int]($App.failedDeviceCount) -le 0) { continue }

                $Issues.Add([PSCustomObject]@{
                        Message           = "App '$($App.displayName)' failed to install on $($App.failedDeviceCount) device(s) ($($App.failedDevicePercentage)%)."
                        Tenant            = $TenantFilter
                        Type              = 'Application'
                        AppName           = $App.displayName
                        IssueStatus       = 'failed'
                        FailedDeviceCount = [int]$App.failedDeviceCount
                        FailedUserCount   = [int]$App.failedUserCount
                        FailedPercentage  = $App.failedDevicePercentage
                        Platform          = $App.platform
                    })
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to read cached Intune app install status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    if (-not $Issues) {
        return
    }

    if (-not $Config.AlertEachIssue) {
        $PolicyCount = ($Issues | Where-Object { $_.Type -eq 'Policy' }).Count
        $AppCount = ($Issues | Where-Object { $_.Type -eq 'Application' }).Count

        $AlertData = @([PSCustomObject]@{
                Message      = "Found $PolicyCount policy issues and $AppCount application issues in Intune."
                Tenant       = $TenantFilter
                PolicyIssues = $PolicyCount
                AppIssues    = $AppCount
                Issues       = $Issues
            })
    } else {
        $AlertData = $Issues
    }

    if ($AlertData) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    }
}
