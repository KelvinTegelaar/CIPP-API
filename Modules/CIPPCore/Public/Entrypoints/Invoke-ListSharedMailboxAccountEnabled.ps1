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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.Query.TenantFilter

    # Get Shared Mailbox Stuff
    try {
        $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $TenantFilter -scope ExchangeOnline)
        $AllUsersAccountState = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName,accountEnabled,displayName,givenName,surname,onPremisesSyncEnabled' -tenantid $Tenantfilter
        $EnabledUsersWithSharedMailbox = foreach ($SharedMailbox in $SharedMailboxList) {
            # Match the User
            $User = $AllUsersAccountState | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -Property id, userPrincipalName, accountEnabled, displayName, givenName, surname, onPremisesSyncEnabled -First 1
            if ($User.accountEnabled) {
                $User | Select-Object `
                @{Name = 'UserPrincipalName'; Expression = { $User.UserPrincipalName } }, `
                @{Name = 'displayName'; Expression = { $User.displayName } },
                @{Name = 'givenName'; Expression = { $User.givenName } },
                @{Name = 'surname'; Expression = { $User.surname } },
                @{Name = 'accountEnabled'; Expression = { $User.accountEnabled } },
                @{Name = 'id'; Expression = { $User.id } },
                @{Name = 'onPremisesSyncEnabled'; Expression = { $User.onPremisesSyncEnabled } }

            }
        }
    }
    catch {
        Write-LogMessage -API 'Tenant' -tenant $tenantfilter -message "Shared Mailbox Enabled Accounts on $($tenantfilter). Error: $($_.exception.message)" -sev 'Error'
    }

    $GraphRequest = $EnabledUsersWithSharedMailbox
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
