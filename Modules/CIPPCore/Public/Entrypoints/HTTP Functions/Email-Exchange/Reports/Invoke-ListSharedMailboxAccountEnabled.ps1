using namespace System.Net

Function Invoke-ListSharedMailboxAccountEnabled {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $TenantFilter = $Request.Query.tenantFilter

    # Get Shared Mailbox Stuff
    try {
        $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $TenantFilter -scope ExchangeOnline)
        $AllUsersInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$select=id,userPrincipalName,accountEnabled,displayName,givenName,surname,onPremisesSyncEnabled,assignedLicenses' -tenantid $TenantFilter
        $SharedMailboxDetails = foreach ($SharedMailbox in $SharedMailboxList) {
            # Match the User
            $User = $AllUsersInfo | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -First 1

            if ($User) {
                # Return all shared mailboxes with license information
                [PSCustomObject]@{
                    UserPrincipalName = $User.userPrincipalName
                    displayName = $User.displayName
                    givenName = $User.givenName
                    surname = $User.surname
                    accountEnabled = $User.accountEnabled
                    assignedLicenses = $User.assignedLicenses
                    id = $User.id
                    onPremisesSyncEnabled = $User.onPremisesSyncEnabled
                }
            }
        }
    } catch {
        Write-LogMessage -API 'Tenant' -tenant $TenantFilter -message "Shared Mailbox List on $($TenantFilter). Error: $($_.exception.message)" -sev 'Error'
    }
    $GraphRequest = $SharedMailboxDetails
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
