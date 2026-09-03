function Invoke-ExecUserBookmarks {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Bookmarks = $Request.Body.currentSettings.bookmarks
        if ($null -eq $Bookmarks) {
            $Bookmarks = @()
        } elseif ($Bookmarks -isnot [System.Array]) {
            $Bookmarks = @($Bookmarks)
        }

        $object = $Bookmarks | ConvertTo-Json -Compress -Depth 10
        $Table = Get-CippTable -tablename 'UserSettings'
        $User = $Request.Body.user
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$User"
            PartitionKey = 'UserBookmarks'
        }
        $StatusCode = [HttpStatusCode]::OK
        $Result = 'Successfully added user bookmarks'
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Info'
        $Results = [pscustomobject]@{'Results' = $Result }
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Result = "Function Error: $ErrorMsg"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error'
        $Results = $Result
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        }

}
