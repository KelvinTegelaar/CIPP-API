function Invoke-CIPPStandardActivityBasedTimeout {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    # Input validation
    if ([string]::IsNullOrWhiteSpace($Settings.timeout) -or $Settings.timeout -eq 'Select a value' ) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ActivityBasedTimeout: Invalid timeout parameter set' -sev Error
        Return
    }

    # Backwards compatibility for v5.7.0 and older
    if ($null -eq $Settings.timeout ) { $Settings.timeout = '01:00:00' }

    $State = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -tenantid $tenant
    $StateIsCorrect = $State.definition -like "*$($Settings.timeout)*"

    If ($Settings.remediate -eq $true) {
        try {
            if (!$StateIsCorrect) {
                $PolicyTemplate = @{
                    displayName           = 'DefaultTimeoutPolicy'
                    isOrganizationDefault = $true
                    definition            = @(
                        "{`"ActivityBasedTimeoutPolicy`":{`"Version`":1,`"ApplicationPolicies`":[{`"ApplicationId`":`"default`",`"WebSessionIdleTimeout`":`"$($Settings.timeout)`"}]}}"
                    )
                }
                $body = ConvertTo-Json -InputObject $PolicyTemplate -Depth 10 -Compress

                # Switch between parameter sets if the policy already exists
                if ($null -eq $State.id) {
                    $RequestType = 'POST'
                    $URI = 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies'
                } else {
                    $RequestType = 'PATCH'
                    $URI = "https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies/$($State.id)"
                }
                New-GraphPostRequest -tenantid $tenant -Uri $URI -Type $RequestType -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled Activity Based Timeout with a value of $($Settings.timeout)" -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Activity Based Timeout is already enabled and set to $($Settings.timeout)" -sev Info
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Activity Based Timeout a value of $($Settings.timeout). Error: $ErrorMessage" -sev Error
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Activity Based Timeout is enabled and set to $($Settings.timeout)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Activity Based Timeout is not set to $($Settings.timeout)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'ActivityBasedTimeout' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}

