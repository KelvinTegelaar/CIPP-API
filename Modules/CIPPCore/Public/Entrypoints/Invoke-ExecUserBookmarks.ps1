function Invoke-ExecUserBookmarks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)
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
        $Results = [pscustomobject]@{'Results' = 'Successfully added user bookmarks' }
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        }

}
