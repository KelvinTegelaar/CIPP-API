function Invoke-ExecShadowAISanction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Marks an AI tool from the Shadow AI catalog as company sanctioned for a tenant, or removes
        that status. Sanctioned tools are stored per tenant in the ShadowAIConfig table and are
        reported by ListShadowAI with risk 'Informational' and status 'Sanctioned'; all other
        detected AI tools report status 'Unsanctioned'.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $Tools = @($Request.Body.Tools ?? $Request.Body.Tool) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $Action = $Request.Body.Action ?? 'Sanction'

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if ($Tools.Count -eq 0) { throw 'No AI tool specified' }
        if ($Action -notin @('Sanction', 'Unsanction')) { throw "Unknown action '$Action'. Use Sanction or Unsanction." }

        $Table = Get-CIPPTable -TableName 'ShadowAIConfig'
        $Results = foreach ($Tool in $Tools) {
            # Table storage forbids /, \, # and ? in row keys
            $RowKey = ($Tool -replace '[\\/#\?]', ' ').Trim()
            if ($Action -eq 'Sanction') {
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    PartitionKey = $TenantFilter
                    RowKey       = $RowKey
                    Tool         = "$Tool"
                    Sanctioned   = $true
                } -Force
                Write-LogMessage -headers $Request.Headers -API 'ExecShadowAISanction' -tenant $TenantFilter -message "Marked AI tool '$Tool' as company sanctioned" -Sev 'Info'
                "Marked '$Tool' as company sanctioned. Its risk level now reports as Informational."
            } else {
                $EscapedTenant = $TenantFilter -replace "'", "''"
                $EscapedRowKey = $RowKey -replace "'", "''"
                $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$EscapedTenant' and RowKey eq '$EscapedRowKey'"
                if ($Entity) {
                    Remove-AzDataTableEntity @Table -Entity $Entity -Force
                }
                Write-LogMessage -headers $Request.Headers -API 'ExecShadowAISanction' -tenant $TenantFilter -message "Removed company sanctioned status from AI tool '$Tool'" -Sev 'Info'
                "Removed company sanctioned status from '$Tool'. Its catalog risk level applies again."
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = @($Results) }
            })
    } catch {
        Write-LogMessage -headers $Request.Headers -API 'ExecShadowAISanction' -tenant $TenantFilter -message "Failed to update sanctioned AI tools: $($_.Exception.Message)" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @("Failed to update sanctioned AI tools: $($_.Exception.Message)") }
            })
    }
}
