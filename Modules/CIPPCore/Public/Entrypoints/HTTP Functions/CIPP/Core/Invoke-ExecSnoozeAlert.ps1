function Invoke-ExecSnoozeAlert {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $CmdletName = $Request.Body.CmdletName
        $TenantFilter = $Request.Body.TenantFilter
        $AlertItem = $Request.Body.AlertItem
        $Duration = [int]$Request.Body.Duration
        $SnoozedBy = try {
            ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        } catch { 'Unknown' }

        if ([string]::IsNullOrWhiteSpace($CmdletName) -or [string]::IsNullOrWhiteSpace($TenantFilter) -or $null -eq $AlertItem) {
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'CmdletName, TenantFilter, and AlertItem are required.' }
            })
        }

        if ($Duration -notin @(7, 14, 30, -1)) {
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Duration must be 7, 14, 30, or -1 (forever).' }
            })
        }

        # Compute content hash for this alert item
        $HashResult = Get-AlertContentHash -AlertItem $AlertItem

        # Calculate SnoozeUntil
        $CurrentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        $SnoozeUntil = if ($Duration -eq -1) {
            [int64](-1)
        } else {
            $CurrentUnixTime + ($Duration * 86400)
        }

        $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'
        $SnoozeEntity = @{
            PartitionKey   = [string]$CmdletName
            RowKey         = [string]"$($TenantFilter)-$($HashResult.ContentHash)" -replace '[\\/#?\u0000-\u001f\u007f-\u009f]', '_'
            ContentHash    = [string]$HashResult.ContentHash
            Tenant         = [string]$TenantFilter
            SnoozeUntil    = [string]$SnoozeUntil
            SnoozedBy      = [string]$SnoozedBy
            SnoozedAt      = [string]$CurrentUnixTime
            ContentPreview = [string]$HashResult.ContentPreview
            SnoozeKey      = [string]$HashResult.RawKey
        }

        Add-CIPPAzDataTableEntity @SnoozeTable -Entity $SnoozeEntity -Force | Out-Null

        $DurationLabel = if ($Duration -eq -1) { 'forever' } else { "$Duration days" }
        $ContentPreview = $HashResult.ContentPreview
        $Result = "Successfully snoozed alert for ${DurationLabel}: ${ContentPreview}"

        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results      = $Result
                ContentHash  = $HashResult.ContentHash
                SnoozeUntil  = $SnoozeUntil
                SnoozedBy    = $SnoozedBy
            }
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to snooze alert: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed to snooze alert: $($ErrorMessage.NormalizedError)" }
        })
    }
}
