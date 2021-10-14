using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$tenantfilter = $Request.Query.TenantFilter
$appFilter = $Request.Query.ID
$AssignTo = $Request.Query.AssignTo
$AssignBody = switch ($AssignTo) {

    'AllUsers' {
        @"
{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"},"intent":"Required","settings":null}]}
"@ 
    }

    'AllDevices' {
        @"
{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"},"intent":"Required","settings":null}]}
"@
    }

    'Both' {
        @"
{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"},"intent":"Required","settings":null},{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"},"intent":"Required","settings":null}]}
"@
    }

}

Write-Host $AssignBody
$GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appFilter/assign" -tenantid $TenantFilter -body $Assignbody
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $GraphRequest
    })
