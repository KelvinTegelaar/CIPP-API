function Invoke-ExecStandardsRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers



    $TenantFilter = $Request.Query.tenantFilter ?? 'allTenants'
    $TemplateId = $Request.Query.templateId ?? $Request.Query.TemplateId ?? '*'
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TimeStamp).JSON | ForEach-Object {
        try {
            ConvertFrom-Json $_ -ErrorAction SilentlyContinue
        } catch {

        }
    } | Where-Object {
        $_.guid -like $TemplateId
    }

    # [bool] over an array (or the string 'false') is always $true, which flipped wildcard runs to manual-only.
    $RunManually = @($Templates).Count -eq 1 -and ("$(@($Templates)[0].runManually)" -eq 'True')

    # Call the wrapper - it handles queuing internally via Start-CIPPOrchestrator
    try {
        $null = New-CIPPStandardsRun -TenantFilter $TenantFilter -TemplateID $TemplateId -runManually $RunManually -Force
        $TemplateName = if ($TemplateId -eq '*') { 'All' } else { "$($Templates.templateName) ($($Templates.GUID))" }
        $RunMode = if ($RunManually) { ' (Manual Only)' } else { '' }
        $Results = "Successfully started Standards Run for tenant: $TenantFilter - Template: $TemplateName$RunMode"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Results -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to start standards run for tenant: $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
    }

    $Results = [pscustomobject]@{'Results' = "$Results" }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
