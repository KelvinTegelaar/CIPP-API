function Invoke-ListAutopilotconfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.Read
    .DESCRIPTION
        Lists Windows Autopilot deployment profiles, Enrollment Status Page configurations, or Windows Hello for Business policies for a tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        if ($Request.Query.type -eq 'ApProfile') {
            # Graph's groupAssignmentTarget carries only groupId, so fetch group names in the same batch
            # and resolve them into PolicyAssignment like the MEM policy list does.
            # ponytail: $top=999 group cap, same ceiling ListIntunePolicy accepts; page if a tenant exceeds it
            $BulkRequests = @(
                [PSCustomObject]@{ id = 'Profiles'; method = 'GET'; url = '/deviceManagement/windowsAutopilotDeploymentProfiles?$expand=assignments' }
                [PSCustomObject]@{ id = 'Groups'; method = 'GET'; url = '/groups?$top=999&$select=id,displayName' }
            )
            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

            $GroupLookup = @{}
            $GroupResult = $BulkResults | Where-Object { $_.id -eq 'Groups' } | Select-Object -First 1
            foreach ($Group in @($GroupResult.body.value)) {
                if ($Group.id) { $GroupLookup[$Group.id] = $Group.displayName }
            }

            $ProfileResult = $BulkResults | Where-Object { $_.id -eq 'Profiles' } | Select-Object -First 1
            if ($null -ne $ProfileResult.status -and ($ProfileResult.status -lt 200 -or $ProfileResult.status -ge 300)) {
                throw ($ProfileResult.body.error.message ?? "Graph returned status $($ProfileResult.status) listing Autopilot profiles")
            }
            $GraphRequest = foreach ($Profile in @($ProfileResult.body.value)) {
                if ($null -eq $Profile) { continue }
                ConvertTo-CIPPIntunePolicyListItem -Policy $Profile -URLName 'windowsAutopilotDeploymentProfiles' -DefaultPolicyTypeName 'Autopilot Profile' -GroupLookup $GroupLookup
            }
        }

        if ($Request.Query.type -eq 'ESP') {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments" -tenantid $TenantFilter |
                Where-Object -Property '@odata.type' -EQ '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
