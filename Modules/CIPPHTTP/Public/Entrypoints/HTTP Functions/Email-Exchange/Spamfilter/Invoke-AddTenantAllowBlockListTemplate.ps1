function Invoke-AddTenantAllowBlockListTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    try {
        $GUID = (New-Guid).GUID
        $JSON = @{
            entries      = $Request.body.entries
            listType     = $Request.body.listType
            listMethod   = $Request.body.listMethod
            notes        = $Request.body.notes
            NoExpiration = [bool]$Request.body.NoExpiration
            RemoveAfter  = [bool]$Request.body.RemoveAfter
            templateName = $Request.body.templateName
        } | ConvertTo-Json -Depth 10

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'TenantAllowBlockListTemplate'
        }
        Write-LogMessage -Headers $Headers -API $APIName -message "Created Tenant Allow/Block List Template $($Request.body.templateName) with GUID $GUID" -Sev Info
        $body = [pscustomobject]@{ 'Results' = "Created Tenant Allow/Block List Template $($Request.body.templateName) with GUID $GUID" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -message "Failed to create Tenant Allow/Block List Template: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $body = [pscustomobject]@{ 'Results' = "Failed to create Tenant Allow/Block List Template: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
