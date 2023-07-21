param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.usersubmissions
if (!$Setting) {
    $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.usersubmissions
}
if ($Setting.enable -and $Setting.disable) {
    Write-LogMessage -API "Standards" -tenant $tenant -message "You cannot both enable and disable the User Submission policy" -sev Error
    Exit
}
elseif ($setting.enable) {
    $status = $true
    try {
        $Policy = New-ExoRequest -tenantid $Tenant -cmdlet "Get-ReportSubmissionPolicy"
        if ($Policy.length -eq 0) {
            New-ExoRequest -tenantid $Tenant -cmdlet "New-ReportSubmissionPolicy"
            Write-LogMessage -API "Standards" -tenant $tenant -message "User Submission policy set to $status." -sev Info
        }
        else {
            New-ExoRequest -tenantid $Tenant -cmdlet "Set-ReportSubmissionPolicy" -cmdParams @{ EnableReportToMicrosoft = $status; Identity = $($Policy.Identity); }
            Write-LogMessage -API "Standards" -tenant $tenant -message "User Submission policy set to $status." -sev Info
        }
    }
    catch {
        Write-LogMessage -API "Standards" -tenant $tenant -message "Could not set User Submission policy to $status. Error: $($_.exception.message)" -sev Error
    }
}
else {
    $status = $false
    try {
        $Policy = New-ExoRequest -tenantid $Tenant -cmdlet "Get-ReportSubmissionPolicy"
        if ($Policy.length -eq 0) {
            Write-LogMessage -API "Standards" -tenant $tenant -message "User Submission policy set to $status." -sev Info
        }
        else {
            New-ExoRequest -tenantid $Tenant -cmdlet "Set-ReportSubmissionPolicy" -cmdParams @{ EnableReportToMicrosoft = $status; Identity = $($Policy.Identity); EnableThirdPartyAddress = $status; ReportJunkToCustomizedAddress = $status; ReportNotJunkToCustomizedAddress = $status; ReportPhishToCustomizedAddress = $status; }
            Write-LogMessage -API "Standards" -tenant $tenant -message "User Submission policy set to $status." -sev Info
        }
    }
    catch {
        Write-LogMessage -API "Standards" -tenant $tenant -message "Could not set User Submission policy to $status. Error: $($_.exception.message)" -sev Error
    }
}