function Invoke-ListSharedMailboxAccountEnabled {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter

    # Get Shared Mailbox Stuff
    try {
        $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $TenantFilter -scope ExchangeOnline)
        $AllUsersInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$select=id,userPrincipalName,accountEnabled,displayName,givenName,surname,onPremisesSyncEnabled,assignedLicenses' -tenantid $TenantFilter
        $SharedMailboxDetails = foreach ($SharedMailbox in $SharedMailboxList) {
            # Match the User
            $User = $AllUsersInfo | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -First 1

            if ($User.accountEnabled) {
                # Return all shared mailboxes with license information
                [PSCustomObject]@{
                    UserPrincipalName     = $User.userPrincipalName
                    displayName           = $User.displayName
                    givenName             = $User.givenName
                    surname               = $User.surname
                    accountEnabled        = $User.accountEnabled
                    assignedLicenses      = $User.assignedLicenses
                    id                    = $User.id
                    onPremisesSyncEnabled = $User.onPremisesSyncEnabled
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Shared Mailbox List on $($TenantFilter). Error: $($_.exception.message)" -sev 'Error'
    }
    $GraphRequest = $SharedMailboxDetails
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
