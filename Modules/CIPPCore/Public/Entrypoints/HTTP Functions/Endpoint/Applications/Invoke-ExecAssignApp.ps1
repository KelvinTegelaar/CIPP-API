using namespace System.Net

Function Invoke-ExecAssignApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $appFilter = $Request.Query.ID ?? $Request.Body.ID
    $AssignTo = $Request.Query.AssignTo ?? $Request.Body.AssignTo
    $AssignBody = switch ($AssignTo) {

        'AllUsers' {
            @'
{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"},"intent":"Required","settings":null}]}
'@
        }

        'AllDevices' {
            @'
{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"},"intent":"Required","settings":null}]}
'@
        }

        'Both' {
            @'
{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"},"intent":"Required","settings":null},{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"},"intent":"Required","settings":null}]}
'@
        }

    }
    try {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appFilter/assign" -tenantid $TenantFilter -body $AssignBody
        $Result = "Successfully assigned app $($appFilter) to $($AssignTo)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to assign app $($appFilter) to $($AssignTo). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
