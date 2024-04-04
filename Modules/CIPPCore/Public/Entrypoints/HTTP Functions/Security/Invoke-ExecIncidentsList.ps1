using namespace System.Net

Function Invoke-ExecIncidentsList {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    try {
        # Interact with query parameters or the body of the request.
        $TenantFilter = $Request.Query.TenantFilter
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            $incidents = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/incidents' -tenantid $Request.Query.TenantFilter -AsApp $true

            foreach ($incident in $incidents) {    
                [PSCustomObject]@{
                    Tenant         = $Request.Query.TenantFilter
                    Id             = $incident.id
                    Status         = $incident.status
                    IncidentUrl    = $incident.incidentWebUrl
                    RedirectId     = $incident.redirectIncidentId
                    DisplayName    = $incident.displayName
                    Created        = $incident.createdDateTime
                    Updated        = $incident.lastUpdateDateTime
                    AssignedTo     = $incident.assignedTo
                    Classification = $incident.classification
                    Determination  = $incident.determination
                    Severity       = $incident.severity
                    Tags           = ($IncidentObj.tags -join ', ')
                    Comments       = $incident.comments
                }
            }       
        } else {
            $Table = Get-CIPPTable -TableName cachealertsandincidents
            $Filter = "PartitionKey eq 'Incident'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-10)
            if (!$Rows) {
                Push-OutputBinding -Name incidentqueue -Value (Get-Date).ToString()
                [PSCustomObject]@{
                    Waiting = $true
                }
            } else {
                $incidents = $Rows
                foreach ($incident in $incidents) {  
                    $IncidentObj = $incident.Incident | ConvertFrom-Json  
                    [PSCustomObject]@{
                        Tenant         = $incident.Tenant
                        Id             = $IncidentObj.id
                        Status         = $IncidentObj.status
                        IncidentUrl    = $IncidentObj.incidentWebUrl
                        RedirectId     = $IncidentObj.redirectIncidentId
                        DisplayName    = $IncidentObj.displayName
                        Created        = $IncidentObj.createdDateTime
                        Updated        = $IncidentObj.lastUpdateDateTime
                        AssignedTo     = $IncidentObj.assignedTo
                        Classification = $IncidentObj.classification
                        Determination  = $IncidentObj.determination
                        Severity       = $IncidentObj.severity
                        Tags           = ($IncidentObj.tags -join ', ')
                        Comments       = @($IncidentObj.comments)
                    }
                } 
            }
        }
    } catch {
        $StatusCode = [HttpStatusCode]::Forbidden
        $body = $_.Exception.message
    }
    if (!$body) {
        $StatusCode = [HttpStatusCode]::OK
        $body = [PSCustomObject]@{
            MSResults = ($GraphRequest | Where-Object -Property id -NE $null)
        }
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        }) 

}
