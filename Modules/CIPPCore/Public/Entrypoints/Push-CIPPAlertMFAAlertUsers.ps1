function Push-CIPPAlertMFAAlertUsers {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        $users = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$select=userPrincipalName,id,accountEnabled,userType&`$filter=userType eq 'Member' and accountEnabled eq true" -tenantid $($QueueItem.tenant)
        Write-Host "found $($users.count) users"
        $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'

        $UserBatches = [System.Collections.Generic.List[Object]]@()
        for ($i = 0; $i -lt $users.count; $i += 20) {
            $UserBatches.Add($users[$i..($i + 19)])
        }

        $UserBatches | ForEach-Object -Parallel {
            Import-Module CippCore
            Import-Module AzBobbyTables
            $UserBatch = $_
            Write-Host "processing batch of $($UserBatch.count) users"
            $BatchRequests = $UserBatch | ForEach-Object {
                @{
                    id     = $_.id
                    method = 'GET'
                    url    = "users/$($_.ID)/authentication/Methods"
                }
            }
            $BatchResponses = New-GraphBulkRequest -tenantid $using:QueueItem.tenant -Requests $BatchRequests
            foreach ($response in $BatchResponses) {
                $UPN = ($UserBatch | Where-Object { $_.id -eq $response.id }).UserPrincipalName
                $CARegistered = $false

                foreach ($method in $response.body.value) {
                    if ($method.'@odata.type' -in $using:StrongMFAMethods) {
                        $CARegistered = $true
                        break
                    }
                }

                if (-not $CARegistered) {
                    Write-AlertMessage -tenant $using:QueueItem.tenant -message "User $UPN is enabled but does not have any form of MFA configured."
                }
            }
        } -ThrottleLimit 25

    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Could not get MFA status for users for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
