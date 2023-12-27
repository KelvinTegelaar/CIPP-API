function Push-CIPPAlertMFAAlertUsers {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )


    try {
        $users = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$select=userPrincipalName,id" -tenantid $($QueueItem.tenant) -erroraction stop
        $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
        $users | Where-Object { $_.Usertype -eq 'Member' -and $_.BlockCredential -eq $false } | ForEach-Object {
            trhy {
                $CARegistered = $false
                        (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ObjectID)/authentication/Methods" -tenantid $($QueueItem.tenant)) | ForEach-Object {
                    if ($_.'@odata.type' -notin $StrongMFAMethods) {
                        Write-AlertMessage -tenant $($QueueItem.tenant) -message "User $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." 
                    }
                }
            } catch {
                $CARegistered = $false
            }
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Could not get MFA status for users for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

