function Invoke-ExecRunTenantGroupRule {
    <#
    .SYNOPSIS
        Execute tenant group dynamic rules immediately
    .DESCRIPTION
        This function executes dynamic tenant group rules for immediate membership updates
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Groups.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $GroupId = $Request.Body.groupId ?? $Request.Query.groupId

    try {
        $GroupTable = Get-CippTable -tablename 'TenantGroups'
        $Group = Get-CIPPAzDataTableEntity @GroupTable -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$GroupId'"

        if (-not $Group) { $Body = @{ Results = 'Group not found' } }

        $null = Start-TenantDynamicGroupOrchestrator -GroupId $GroupId

        $Body = @{ Results = "Dynamic rules executed successfully for group '$($Group.Name)'. Processing will continue in the background. Check the logbook for details." }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'TenantGroups' -message "Failed to execute tenant group rules: $ErrorMessage" -sev Error
        $Body = @{ Results = "Failed to execute dynamic rules: $ErrorMessage" }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Body
            })
    }
}
