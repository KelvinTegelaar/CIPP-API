function Invoke-ListSharedMailboxAccountEnabled {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists shared mailboxes that have direct sign-in enabled (account not disabled), which is a security concern.
        Supports UseReportDB=true to read cached data from the reporting database (required for AllTenants).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    # Get Shared Mailbox Stuff
    try {
        # If UseReportDB is specified, retrieve from the report database (cached Mailboxes + Users join)
        if ($UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

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
