function Invoke-ListBECRemediationActions {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Lists the available Business Email Compromise containment actions.
    .DESCRIPTION
        Returns the catalog of containment actions ExecBECRemediate accepts - id, label, description, impact (Low/Medium/High/Critical), whether it is reversible and whether it runs by default (the instance-wide defaults from CIPP settings).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = @(Get-CIPPBecContainmentActions | Select-Object Id, Label, Description, Impact, Reversible, DefaultSelected, Order, TargetSource, ParameterName)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to list containment actions: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
