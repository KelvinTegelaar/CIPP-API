using namespace System.Net

function Invoke-PublicPhishingCheck {
    <#
    .SYNOPSIS
    Process phishing check alerts from external service
    
    .DESCRIPTION
    Processes phishing check alerts from the external free service at clone.cipp.app, handling cloned site detection and alert messaging.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
        
    .NOTES
    Group: Security
    Summary: Public Phishing Check
    Description: Processes phishing check alerts from the external free service at clone.cipp.app, handling cloned site detection and alert messaging for security monitoring.
    Tags: Security,Phishing,Alerts,External Service
    Parameter: Request.body.Cloned (boolean) [body] - Whether a cloned site was detected
    Parameter: Request.body.AlertMessage (string) [body] - Alert message to display
    Parameter: Request.body.TenantId (string) [body] - Tenant identifier for the alert
    Response: Returns 'OK' with HTTP 200 status on successful processing
    Response: Actions performed:
    Response: - Writes alert message if cloned site is detected
    Response: - Processes alert for the specified tenant
    Example: The function processes phishing alerts and returns:
    Example: - HTTP 200 status with 'OK' response
    Example: - Alert message written to logs if cloned site detected
    Note: This function has been switched to use the external free service by cyberdrain at clone.cipp.app due to extreme numbers of executions if self-hosted.
    #>
    [CmdletBinding()]

    #this has been switched to the external free service by cyberdrain at clone.cipp.app due to extreme numbers of executions if selfhosted.
    param($Request, $TriggerMetadata)
    if ($Request.body.Cloned) {
        Write-AlertMessage -message $Request.body.AlertMessage -sev 'Alert' -tenant $Request.body.TenantId
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'OK'
        })
}
