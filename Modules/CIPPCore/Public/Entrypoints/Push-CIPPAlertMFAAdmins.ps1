function Push-CIPPAlertMFAAdmins {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        $LastRunTable = Get-CIPPTable -Table AlertLastRun
        $Filter = "RowKey eq 'MFAAllAdmins' and PartitionKey eq '{0}'" -f $QueueItem.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
            $AdminList = (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$expand=members" -tenantid $($QueueItem.tenant) | Where-Object -Property roleTemplateId -NE 'd29b2b05-8046-44ba-8758-1e26182fcf32').members | Where-Object { $_.userPrincipalName -ne $null -and $_.Usertype -eq 'Member' -and $_.accountEnabled -eq $true } | Sort-Object UserPrincipalName -Unique
            $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $QueueItem.tenant -ErrorAction Stop)
            foreach ($Policy in $CAPolicies) {
                if ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa') {
                    $DuoActive = $true
                }
            } 
            if (!$DuoActive) {
                $AdminList | ForEach-Object {
                    $CARegistered = $null
                    try {
                        New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ID)/authentication/Methods" -tenantid $($QueueItem.tenant) | ForEach-Object {
                            if ($_.'@odata.type' -in $StrongMFAMethods) {
                                $CARegistered = $true
                            }
                        }
                        if ($CARegistered -ne $true) { 
                            Write-AlertMessage -tenant $($QueueItem.tenant) -message "Admin $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." 
                        }
                    } catch {
                        # Error handling here if needed
                    }
                }
            } else {
                Write-LogMessage -message 'Potentially using Duo for MFA, could not check MFA status for Admins with 100% accuracy' -API 'MFA Alerts - Informational' -tenant $QueueItem.tenant -sev Info
            }
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Could not get MFA status for admins for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
    $LastRun = @{
        RowKey       = 'MFAAllAdmins'
        PartitionKey = $QueueItem.tenantid
    }
    Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
}