function Invoke-CIPPStandardActivityBasedTimeout {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ActivityBasedTimeout
    .SYNOPSIS
        (Label) Enable Activity based Timeout
    .DESCRIPTION
        (Helptext) Enables and sets Idle session timeout for Microsoft 365 to 1 hour. This policy affects most M365 web apps
        (DocsDescription) Enables and sets Idle session timeout for Microsoft 365 to 1 hour. This policy affects most M365 web apps
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS M365 5.0 (1.3.2)"
            "spo_idle_session_timeout"
            "NIST CSF 2.0 (PR.AA-03)"
        EXECUTIVETEXT
            Automatically logs out inactive users from Microsoft 365 applications after a specified time period to prevent unauthorized access to company data on unattended devices. This security measure protects against data breaches when employees leave workstations unlocked.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.ActivityBasedTimeout.timeout","options":[{"label":"1 Hour","value":"01:00:00"},{"label":"3 Hours","value":"03:00:00"},{"label":"6 Hours","value":"06:00:00"},{"label":"12 Hours","value":"12:00:00"},{"label":"24 Hours","value":"1.00:00:00"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-04-13
        POWERSHELLEQUIVALENT
            Portal or Graph API
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'ActivityBasedTimeout' -Settings $Settings

    # Get timeout value using null-coalescing operator
    $timeout = $Settings.timeout.value ?? $Settings.timeout

    # Input validation
    if ([string]::IsNullOrWhiteSpace($timeout) -or $timeout -eq 'Select a value' ) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'ActivityBasedTimeout: Invalid timeout parameter set' -sev Error
        return
    }

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the ActivityBasedTimeout state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }
    $CurrentValue = ($CurrentState.definition | ConvertFrom-Json -ErrorAction SilentlyContinue).activitybasedtimeoutpolicy.ApplicationPolicies | Select-Object -First 1 -Property WebSessionIdleTimeout
    $StateIsCorrect = if ($CurrentValue.WebSessionIdleTimeout -eq $timeout) { $true } else { $false }
    $ExpectedValue = [PSCustomObject]@{WebSessionIdleTimeout = $timeout }

    if ($Settings.remediate -eq $true) {
        try {
            if ($StateIsCorrect -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Activity Based Timeout is already enabled and set to $timeout" -sev Info
            } else {
                $PolicyTemplate = @{
                    displayName           = 'DefaultTimeoutPolicy'
                    isOrganizationDefault = $true
                    definition            = @(
                        "{`"ActivityBasedTimeoutPolicy`":{`"Version`":1,`"ApplicationPolicies`":[{`"ApplicationId`":`"default`",`"WebSessionIdleTimeout`":`"$timeout`"}]}}"
                    )
                }
                $body = ConvertTo-Json -InputObject $PolicyTemplate -Depth 10 -Compress

                # Switch between parameter sets if the policy already exists
                if ($null -eq $CurrentState.id) {
                    $RequestType = 'POST'
                    $URI = 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies'
                } else {
                    $RequestType = 'PATCH'
                    $URI = "https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies/$($CurrentState.id)"
                }
                New-GraphPostRequest -tenantid $Tenant -Uri $URI -Type $RequestType -Body $body
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Enabled Activity Based Timeout with a value of $timeout" -sev Info
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable Activity Based Timeout a value of $timeout." -sev Error -LogData $ErrorMessage
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Activity Based Timeout is enabled and set to $timeout" -sev Info
        } else {
            Write-StandardsAlert -message "Activity Based Timeout is not set to $timeout" -object ($CurrentState.definition | ConvertFrom-Json -ErrorAction SilentlyContinue).activitybasedtimeoutpolicy.ApplicationPolicies -tenant $Tenant -standardName 'ActivityBasedTimeout' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Activity Based Timeout is not set to $timeout" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.ActivityBasedTimeout' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ActivityBasedTimeout' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }

}
