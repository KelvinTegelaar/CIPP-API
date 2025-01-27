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
            "mediumimpact"
            "CIS"
            "spo_idle_session_timeout"
        ADDEDCOMPONENT
            {"type":"select","multiple":false,"label":"Select value","name":"standards.ActivityBasedTimeout.timeout","options":[{"label":"1 Hour","value":"01:00:00"},{"label":"3 Hours","value":"03:00:00"},{"label":"6 Hours","value":"06:00:00"},{"label":"12 Hours","value":"12:00:00"},{"label":"24 Hours","value":"1.00:00:00"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Portal or Graph API
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/global-standards#medium-impact
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'ActivityBasedTimeout' -Settings $Settings

    # Input validation
    if ([string]::IsNullOrWhiteSpace($Settings.timeout) -or $Settings.timeout -eq 'Select a value' ) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ActivityBasedTimeout: Invalid timeout parameter set' -sev Error
        Return
    }

    # Backwards compatibility for v5.7.0 and older
    if ($null -eq $Settings.timeout ) { $Settings.timeout = '01:00:00' }

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -tenantid $tenant
    $StateIsCorrect = if ($CurrentState.definition -like "*$($Settings.timeout)*") { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        try {
            if ($StateIsCorrect -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Activity Based Timeout is already enabled and set to $($Settings.timeout)" -sev Info
            } else {
                $PolicyTemplate = @{
                    displayName           = 'DefaultTimeoutPolicy'
                    isOrganizationDefault = $true
                    definition            = @(
                        "{`"ActivityBasedTimeoutPolicy`":{`"Version`":1,`"ApplicationPolicies`":[{`"ApplicationId`":`"default`",`"WebSessionIdleTimeout`":`"$($Settings.timeout)`"}]}}"
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
                New-GraphPostRequest -tenantid $tenant -Uri $URI -Type $RequestType -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled Activity Based Timeout with a value of $($Settings.timeout)" -sev Info
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Activity Based Timeout a value of $($Settings.timeout)." -sev Error -LogData $_
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Activity Based Timeout is enabled and set to $($Settings.timeout)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Activity Based Timeout is not set to $($Settings.timeout)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'ActivityBasedTimeout' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
