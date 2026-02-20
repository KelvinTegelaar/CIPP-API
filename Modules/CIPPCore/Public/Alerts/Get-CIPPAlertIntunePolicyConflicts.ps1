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

    $AlertableStatuses = @()
    if ($Config.AlertErrors) { $AlertableStatuses += 'error', 'failed' }
    if ($Config.AlertConflicts) { $AlertableStatuses += 'conflict' }

    if (-not $AlertableStatuses) {
        return
    }

    $HasLicense = Test-CIPPStandardLicense -StandardName 'IntunePolicyStatus' -TenantFilter $TenantFilter -RequiredCapabilities @(
        'INTUNE_A',
        'MDM_Services',
        'EMS',
        'SCCM',
        'MICROSOFTINTUNEPLAN1'
    )

    if (-not $HasLicense) {
        return
    }

    $Issues = @()

    if ($Config.IncludePolicies) {
        try {
            $ManagedDevices = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,userPrincipalName&`$expand=deviceConfigurationStates(`$select=displayName,state,settingStates)" -tenantid $TenantFilter

            foreach ($Device in $ManagedDevices) {
                $PolicyStates = $Device.deviceConfigurationStates | Where-Object { $_.state -and ($AlertableStatuses -contains $_.state) }
                foreach ($State in $PolicyStates) {
                    $Issues += [PSCustomObject]@{
                        Message           = "Policy '$($State.displayName)' is $($State.state) on device '$($Device.deviceName)' for $($Device.userPrincipalName)."
                        Tenant            = $TenantFilter
                        Type              = 'Policy'
                        PolicyName        = $State.displayName
                        IssueStatus       = $State.state
                        DeviceName        = $Device.deviceName
                        UserPrincipalName = $Device.userPrincipalName
                        DeviceId          = $Device.id
                    }
                }
            }
        } catch {
            Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to query Intune policy states: $(Get-NormalizedError -message $_.Exception.Message)" -sev Error
        }
    }

    if ($Config.IncludeApplications) {
        try {
            $Applications = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$select=id,displayName&`$expand=deviceStatuses(`$select=installState,deviceName,userPrincipalName,deviceId)" -tenantid $TenantFilter

            foreach ($App in $Applications) {
                $BadStatuses = $App.deviceStatuses | Where-Object {
                    $_.installState -and ($AlertableStatuses -contains $_.installState.ToLowerInvariant())
                }

                foreach ($Status in $BadStatuses) {
                    $Issues += [PSCustomObject]@{
                        Message           = "App '$($App.displayName)' install is $($Status.installState) on device '$($Status.deviceName)' for $($Status.userPrincipalName)."
                        Tenant            = $TenantFilter
                        Type              = 'Application'
                        AppName           = $App.displayName
                        IssueStatus       = $Status.installState
                        DeviceName        = $Status.deviceName
                        UserPrincipalName = $Status.userPrincipalName
                        DeviceId          = $Status.deviceId
                    }
                }
            }
        } catch {
            Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to query Intune application states: $(Get-NormalizedError -message $_.Exception.Message)" -sev Error
        }
    }

    if (-not $Issues) {
        return
    }

    if (-not $Config.AlertEachIssue) {
        $PolicyCount = ($Issues | Where-Object { $_.Type -eq 'Policy' }).Count
        $AppCount = ($Issues | Where-Object { $_.Type -eq 'Application' }).Count

        $AlertData = @([PSCustomObject]@{
                Message        = "Found $PolicyCount policy issues and $AppCount application issues in Intune."
                Tenant         = $TenantFilter
                PolicyIssues   = $PolicyCount
                AppIssues      = $AppCount
                Issues         = $Issues
            })
    } else {
        $AlertData = $Issues
    }

    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
