function Push-CIPPAlertMFAAlertUsers {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        $LastRunTable = Get-CIPPTable -Table AlertLastRun
        $Filter = "RowKey eq 'MFAAllUsers' and PartitionKey eq '{0}'" -f $QueueItem.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$filter=isMfaRegistered eq false' -tenantid $($QueueItem.tenant) 
            if ($users) {
                Write-AlertMessage -tenant $QueueItem.tenant -message "The following users do not have MFA registered: $($users.UserPrincipalName -join ', ')"
            }
        }
    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $QueueItem.tenant -sev Info
    }
    $LastRun = @{
        RowKey       = 'MFAAllUsers'
        PartitionKey = $QueueItem.tenantid
    }
    Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
}
