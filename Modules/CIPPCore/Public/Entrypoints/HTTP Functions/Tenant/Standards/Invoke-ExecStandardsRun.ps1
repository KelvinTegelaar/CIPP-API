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
    $TemplateId = $Request.Query.templateId ?? '*'
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



    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {

            $ProcessorFunction = [PSCustomObject]@{
                PartitionKey = 'Function'
                RowKey       = "Invoke-CIPPStandardsRun-$TenantFilter-$TemplateId"
                FunctionName = 'Invoke-CIPPStandardsRun'
                Parameters   = [string](ConvertTo-Json -Compress -InputObject @{
                        TenantFilter = $TenantFilter
                        TemplateId   = $TemplateId
                        runManually  = [bool]$Templates.runManually
                        Force        = $true
                    })
            }
            $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
            Add-AzDataTableEntity @ProcessorQueue -Entity $ProcessorFunction -Force
            $Results = "Successfully Queued Standards Run for Tenant $TenantFilter"
        }
    } else {
        try {
            $null = Invoke-CIPPStandardsRun -TenantFilter $TenantFilter -TemplateID $TemplateId -runManually ([bool]$Templates.runManually) -Force
            $Results = "Successfully started Standards Run for tenant: $TenantFilter"
            Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Results -Sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results = "Failed to start standards run for tenant: $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        }
    }

    $Results = [pscustomobject]@{'Results' = "$Results" }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
