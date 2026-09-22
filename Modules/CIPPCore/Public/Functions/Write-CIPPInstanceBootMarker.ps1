function Write-CIPPInstanceBootMarker {
    <#
    .SYNOPSIS
        Records that this instance started, next to the health samples it interrupts.
    .DESCRIPTION
        The health timer stops writing while a container is down, so the gap between the last
        sample and this boot is the outage the instance cannot otherwise observe. Storing the
        marker in the same table and bucket layout lets the diagnostics timeline line restarts
        up against the samples on either side.

        Warmup runs on every node, so the row is keyed on the boot's 5 minute bucket and
        upserted - racing nodes write the same marker instead of duplicating it.

        Never throws; warmup steps are soft-fail by design.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Write-CIPPInstanceBootMarker
    #>
    [CmdletBinding()]
    param()

    try {
        $Now = [DateTime]::UtcNow
        $Bucket = $Now.AddMinutes(-($Now.Minute % 5)).ToString('yyyy-MM-ddTHH:mm')

        $Table = Get-CIPPTable -TableName 'InstanceHealth'

        # All rows share one partition now, so this is a single partition-scoped RowKey range
        # instead of a cross-partition scan. Bucket keys sort lexically because they are ISO.
        $Since = $Now.AddHours(-24).ToString('yyyy-MM-ddTHH:mm')
        $Previous = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'InstanceHealth' and RowKey ge '$Since' and Kind eq 'sample'" |
            Sort-Object -Property Bucket | Select-Object -Last 1

        $Entity = @{
            PartitionKey = 'InstanceHealth'
            RowKey       = "${Bucket}_boot"
            Bucket       = $Bucket
            Kind         = 'boot'
            BootTime     = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
            Version      = [string]($env:APP_VERSION ?? '')
        }

        if ($Previous.Bucket) {
            $LastSample = [DateTime]::ParseExact($Previous.Bucket, 'yyyy-MM-ddTHH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $Entity.PreviousSample = [string]$Previous.Bucket
            $Entity.GapMinutes = [int][math]::Round(($Now - $LastSample).TotalMinutes)
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        Write-Information "[InstanceHealth] Boot marker recorded for bucket $Bucket"
    } catch {
        Write-Information "[InstanceHealth] Boot marker failed (non-fatal): $($_.Exception.Message)"
    }
}
