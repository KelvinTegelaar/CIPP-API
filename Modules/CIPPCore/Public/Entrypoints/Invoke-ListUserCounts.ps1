using namespace System.Net

Function Invoke-ListUserCounts {
        <#
    .FUNCTIONALITY
    Entrypoint
    #>
        [CmdletBinding()]
        param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'

        # Interact with query parameters or the body of the request.
        $TenantFilter = $Request.Query.TenantFilter
        if ($Request.Query.TenantFilter -eq 'AllTenants') {
                $users = 'Not Supported'
                $LicUsers = 'Not Supported'
                $GAs = 'Not Supported'
                $Guests = 'Not Supported'
        } else {
                $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1" -CountOnly -ComplexFilter -tenantid $TenantFilter
                $LicUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1&`$filter=assignedLicenses/`$count ne 0" -CountOnly -ComplexFilter -tenantid $TenantFilter
                $GAs = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members?`$count=true" -CountOnly -ComplexFilter -tenantid $TenantFilter
                $guests = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1&`$filter=userType eq 'Guest'" -CountOnly -ComplexFilter -tenantid $TenantFilter
        }
        $StatusCode = [HttpStatusCode]::OK
        $Counts = @{
                Users    = $users
                LicUsers = $LicUsers
                Gas      = $Gas
                Guests   = $guests
        }

        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = $StatusCode
                        Body       = $Counts
                })

}
