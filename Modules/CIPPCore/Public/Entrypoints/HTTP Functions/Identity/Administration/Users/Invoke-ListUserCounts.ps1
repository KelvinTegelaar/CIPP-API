using namespace System.Net

Function Invoke-ListUserCounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    if ($Request.Query.TenantFilter -eq 'AllTenants') {
        $Users = 'Not Supported'
        $LicUsers = 'Not Supported'
        $GAs = 'Not Supported'
        $Guests = 'Not Supported'
    } else {
        try { $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1" -CountOnly -ComplexFilter -tenantid $TenantFilter } catch { $Users = 'Not available' }
        try { $LicUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1&`$filter=assignedLicenses/`$count ne 0" -CountOnly -ComplexFilter -tenantid $TenantFilter } catch { $LicUsers = 'Not available' }
        try { $GAs = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members?`$count=true" -CountOnly -ComplexFilter -tenantid $TenantFilter } catch { $GAs = 'Not available' }
        try { $Guests = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1&`$filter=userType eq 'Guest'" -CountOnly -ComplexFilter -tenantid $TenantFilter } catch { $Guests = 'Not available' }
    }
    $StatusCode = [HttpStatusCode]::OK
    $Counts = @{
        Users    = $Users
        LicUsers = $LicUsers
        Gas      = $GAs
        Guests   = $Guests
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Counts
        })

}
