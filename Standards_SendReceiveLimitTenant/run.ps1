param($tenant)
# Get the tenant standards settings
$ConfigTable = Get-CippTable -tablename 'standards'
$Limits = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.SendReceiveLimitTenant.SendReceiveLimit -split ','
if (!$Limits) {
    $Limits = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.SendReceiveLimitTenant.SendReceiveLimit -split ','
}

# Parse the send limits and convert to bytes 
if ($Limits[0] -like "*MB*") {
    $MaxSendSize = [int]($Limits[0] -Replace "[a-zA-Z]", "") * 1MB
}
elseif ($Limits[0] -like "*KB*") {
    $MaxSendSize = [int]($Limits[0] -Replace "[a-zA-Z]", "") * 1KB
} # Default to 35MB if invalid input
else {
    $MaxSendSize = 35MB
}
# Test if the send limit is larger allowed and correct if needed
if ($MaxSendSize -gt 150MB) {
    $MaxSendSize = 150MB
}

# Parse the receive limits and convert to bytes
if ($Limits[1] -like "*MB*") {
    $MaxReceiveSize = [int]($Limits[1] -Replace "[a-zA-Z]", "") * 1MB
}
elseif ($Limits[1] -like "*KB*") {
    $MaxReceiveSize = [int]($Limits[1] -Replace "[a-zA-Z]", "") * 1KB
} # Default to 36MB if invalid input
else {
    $MaxReceiveSize = 36MB
} 
# Test if the receive limit is larger allowed and correct if needed
if ($MaxReceiveSize -gt 150MB) {
    $MaxReceiveSize = 150MB
}

try {
    # Get all mailbox plans
    $AllMailBoxPlans = New-ExoRequest -tenantid $Tenant -cmdlet "Get-MailboxPlan" | Select-Object DisplayName, MaxSendSize, MaxReceiveSize, GUID

    # Loop through all mailbox plans and set the send and receive limits for each if needed
    foreach ($MailboxPlan in $AllMailBoxPlans) {
        if ($MailboxPlan.MaxSendSize -ne $MaxSendSize -and $MailboxPlan.MaxReceiveSize -ne $MaxReceiveSize) {
            New-ExoRequest -tenantid $Tenant -cmdlet "Set-MailboxPlan" -cmdParams @{Identity = $MailboxPlan.GUID; MaxSendSize = $MaxSendSize; MaxReceiveSize = $MaxReceiveSize } -useSystemMailbox $true 
        }
    }
    # Write to log on success
    Write-LogMessage -API "Standards" -tenant $tenant -message "Successfully set the tenant send and receive limits " -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to set the tenant send and receive limits. Error: $($_.exception.message)" -sev Error
}