function Invoke-ExecUserSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $object = $Request.Body.currentSettings | Select-Object * -ExcludeProperty CurrentTenant, pageSizes, sidebarShow, sidebarUnfoldable, _persist | ConvertTo-Json -Compress -Depth 10
        # Saves either the shared allUsers row or the caller's own, never another user's
        $User = $Request.Body.user -eq 'allUsers' ? 'allUsers' : ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        $Table = Get-CippTable -tablename 'UserSettings'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$User"
            PartitionKey = 'UserSettings'
        }
        $StatusCode = [HttpStatusCode]::OK
        $Result = 'Successfully added user settings'
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Info'
        $Results = [pscustomobject]@{'Results' = $Result }
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Result = "Function Error: $ErrorMsg"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error'
        $Results = $Result
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        }

}
