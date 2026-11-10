function Send-CIPPStats {
    <#
    .SYNOPSIS
    Post the stats payload to the central CIPP stats endpoint, staggered so the fleet does not hit it at once.

    .DESCRIPTION
    Every instance runs the stats timer at the same cron, so the central host gets the whole fleet's
    posts inside the same moment and starts dropping them. Each attempt is preceded by a random wait of
    one to five minutes, which spreads the fleet's posts out; a failed attempt is retried after a fresh
    random wait, up to the attempt limit. Stops at the first successful post.

    .PARAMETER Body
    The JSON stats payload to send.

    .PARAMETER MaxAttempts
    How many posts to try before giving up. Defaults to 3.

    .PARAMETER MinDelayMinutes
    Lower bound of the random wait before each attempt. Defaults to 1.

    .PARAMETER MaxDelayMinutes
    Upper bound of the random wait before each attempt. Defaults to 5.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Body,

        [string]$Uri = 'https://management.cipp.app/api/stats',

        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,

        [ValidateRange(0, 60)]
        [int]$MinDelayMinutes = 1,

        [ValidateRange(0, 60)]
        [int]$MaxDelayMinutes = 5
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        # Get-Random's -Maximum is exclusive, so +1 keeps the upper bound reachable; whole seconds spread the fleet evenly.
        $DelaySeconds = Get-Random -Minimum ($MinDelayMinutes * 60) -Maximum (($MaxDelayMinutes * 60) + 1)
        Write-Information "Stats post attempt $Attempt of $MaxAttempts in $DelaySeconds seconds"
        Start-Sleep -Seconds $DelaySeconds

        try {
            $null = Invoke-CIPPRestMethod -Uri $Uri -Method POST -Body $Body -ContentType 'application/json' -ErrorAction Stop
            Write-Information "Stats post succeeded on attempt $Attempt"
            return $true
        } catch {
            $Message = "Stats post attempt $Attempt of $MaxAttempts failed: $($_.Exception.Message)"
            if ($Attempt -lt $MaxAttempts) {
                Write-Information $Message
            } else {
                Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message $Message -sev Warning
            }
        }
    }

    return $false
}
