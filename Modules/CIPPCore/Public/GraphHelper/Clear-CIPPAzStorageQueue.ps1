function Clear-CIPPAzStorageQueue {
    <#
    .SYNOPSIS
        Clears all messages from a specified Azure Storage Queue.
    .DESCRIPTION
        Issues a DELETE request to /<queue>/messages via New-CIPPAzStorageRequest.
        Returns a compact object with StatusCode, Headers, and Request Uri.
    .PARAMETER Name
        The name of the queue to clear.
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage.
    .EXAMPLE
        Clear-CIPPAzStorageQueue -Name 'cippjta72-workitems'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Clear queue messages')) {
        try {
            $headers = @{ Accept = 'application/xml' }
            $resp = New-CIPPAzStorageRequest -Service 'queue' -Resource ("$Name/messages") -Method 'DELETE' -Headers $headers -ConnectionString $ConnectionString
            if ($null -eq $resp) {
                # Fallback when no object returned: assume 204 if no exception was thrown
                return [PSCustomObject]@{ StatusCode = 204; Headers = @{}; Uri = $null; Name = $Name }
            }
            # Normalize to concise output and include the queue name
            $status = $null; $uri = $null; $hdrs = @{}
            if ($resp.PSObject.Properties['StatusCode']) { $status = [int]$resp.StatusCode }
            if ($resp.PSObject.Properties['Uri']) { $uri = $resp.Uri }
            if ($resp.PSObject.Properties['Headers']) { $hdrs = $resp.Headers }
            return [PSCustomObject]@{ Name = $Name; StatusCode = $status; Headers = $hdrs; Uri = $uri }
        } catch {
            throw $_
        }
    }
}
