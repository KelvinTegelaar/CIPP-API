function Invoke-CIPPStandardUserSubmissions {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $Policy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionPolicy'

    If ($Settings.remediate -eq $true) {
        $Status = if ($Settings.state -eq 'enable') { $true } else { $false }

        # If policy is set correctly, log and skip setting the policy
        if ($Policy.EnableReportToMicrosoft -eq $status) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy is already set to $status." -sev Info
        } else {
            if ($Settings.state -eq 'enable') {
                # Policy is not set correctly, enable the policy. Create new policy if it does not exist
                try {
                    if ($Policy.length -eq 0) {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionPolicy' -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                    } else {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams @{ EnableReportToMicrosoft = $status; Identity = $($Policy.Identity); } -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                    }
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set User Submission policy to $status. Error: $ErrorMessage" -sev Error
                }
            } else {
                # Policy is not set correctly, disable the policy.
                try {
                    if ($Policy.length -eq 0) {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                    } else {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams @{ EnableReportToMicrosoft = $status; Identity = $($Policy.Identity); EnableThirdPartyAddress = $status; ReportJunkToCustomizedAddress = $status; ReportNotJunkToCustomizedAddress = $status; ReportPhishToCustomizedAddress = $status; } -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                    }
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set User Submission policy to $status. Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($Policy.length -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'User Submission policy is not set.' -sev Alert
        } else {
            if ($Policy.EnableReportToMicrosoft -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'User Submission policy is enabled.' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'User Submission policy is disabled.' -sev Alert
            }
        }
    }

    if ($Settings.report -eq $true) {
        if ($Policy.length -eq 0) {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
        } else {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $Policy.EnableReportToMicrosoft -StoreAs bool -Tenant $tenant
        }
    }
}