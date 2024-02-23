function Invoke-CIPPStandardActivityBasedTimeout {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $State = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -tenantid $tenant).id

    If ($Settings.remediate) {
        try {
            if (!$State) {
                $body = @'
{
  "displayName": "DefaultTimeoutPolicy",
  "isOrganizationDefault": true,
  "definition":["{\"ActivityBasedTimeoutPolicy\":{\"Version\":1,\"ApplicationPolicies\":[{\"ApplicationId\":\"default\",\"WebSessionIdleTimeout\":\"01:00:00\"}]}}"]
}
'@

                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -Type POST -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Activity Based Timeout of one hour' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Activity Based Timeout is already enabled' -sev Info
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Activity Based Timeout $($_.exception.message)" -sev Error
        }
    }

    if ($Settings.alert) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Activity Based Timeout is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Activity Based Timeout is not enabled' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'ActivityBasedTimeout' -FieldValue [bool]$state -StoreAs bool -Tenant $tenant
    }

}

