function Invoke-CIPPStandardUserSubmissions {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $Policy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionPolicy'
    If ($Settings.remediate) {
        if ($Settings.enable -and $Settings.disable) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'You cannot both enable and disable the User Submission policy' -sev Error
            Exit
        } elseif ($Settings.enable) {
            $status = $true
            try {
                
                if ($Policy.length -eq 0) {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionPolicy'
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                } else {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams @{ EnableReportToMicrosoft = $status; Identity = $($Policy.Identity); }
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set User Submission policy to $status. Error: $($_.exception.message)" -sev Error
            }
        } else {
            $status = $false
            try {
                $Policy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionPolicy'
                if ($Policy.length -eq 0) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                } else {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams @{ EnableReportToMicrosoft = $status; Identity = $($Policy.Identity); EnableThirdPartyAddress = $status; ReportJunkToCustomizedAddress = $status; ReportNotJunkToCustomizedAddress = $status; ReportPhishToCustomizedAddress = $status; }
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy set to $status." -sev Info
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set User Submission policy to $status. Error: $($_.exception.message)" -sev Error
            }
        }
    }
    if ($Settings.alert) {

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
    if ($Settings.report) {
        if ($Policy.length -eq 0) {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
        } else {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue [bool]$Policy.EnableReportToMicrosoft -StoreAs bool -Tenant $tenant
        }
    }
}
