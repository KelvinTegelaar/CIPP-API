function Invoke-ListOneDriveCopyToUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.OneDrive.Read
    .SYNOPSIS
        OneDrive copies and their status
    .DESCRIPTION
        Without OperationId, lists the tenant's OneDrive copies with their last known state, without contacting SharePoint. With OperationId, returns that copy's state overall and per recipient (Queued, InProgress, Completed or Failed), with files and bytes copied and any errors; SharePoint is checked at most once every 30 minutes per copy, otherwise the stored state is returned. Completed and Failed are final. Remove the leaver's licences only once State is Completed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    # The OperationId returned by ExecOneDriveCopyToUser. Omit it to list every copy in the tenant.
    $OperationId = $Request.Query.OperationId

    if (-not $Request.Query.tenantFilter) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }

    try {
        if ($OperationId) {
            $Result = @(Update-CIPPOneDriveCopyToUserStatus -TenantFilter $TenantFilter -OperationId $OperationId)
        } else {
            $Table = Get-CIPPTable -TableName 'OneDriveCopyToUser'
            $SafeKey = (Get-CIPPOneDriveCopyTenantKey -TenantFilter $TenantFilter) -replace "'", "''"
            $Result = @(foreach ($Row in Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeKey' and Kind eq 'Operation'") {
                    $Recipients = if ($Row.RecipientSummary) { @([CIPP.CippJson]::ConvertFromJson([string]$Row.RecipientSummary, $null)) } else { @() }
                    [PSCustomObject]@{
                        OperationId     = $Row.RowKey
                        Leaver          = $Row.LeaverUPN
                        State           = $Row.State ?? 'Queued'
                        Destinations    = @($Recipients.UserPrincipalName) -join ', '
                        Recipients      = $Recipients
                        StartedBy       = $Row.StartedBy
                        StartedUtc      = $Row.StartedUtc
                        LastCheckedUtc  = if ($Row.LastCheckedUnix) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$Row.LastCheckedUnix).UtcDateTime.ToString('o') } else { $null }
                        RootItemCount   = $Row.RootItemCount
                        SourceFileCount = $Row.SourceFileCount
                        SourceBytes     = $Row.SourceBytes
                    }
                })
        }
        $Body = $Result
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to retrieve OneDrive copies: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error -LogData $ErrorMessage
        $Body = @{ Results = $Message }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
