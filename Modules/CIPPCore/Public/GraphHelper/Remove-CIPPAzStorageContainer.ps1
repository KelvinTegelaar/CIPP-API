function Remove-CIPPAzStorageContainer {
    <#
    .SYNOPSIS
        Deletes an Azure Storage blob container.
    .DESCRIPTION
        Issues a DELETE request to /<container>?restype=container via New-CIPPAzStorageRequest.
        Returns a compact object with StatusCode, Headers, and Request Uri.
    .PARAMETER Name
        The name of the container to delete.
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage.
    .EXAMPLE
        Remove-CIPPAzStorageContainer -Name 'cipp-largemessages'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Remove blob container')) {
        try {
            $headers = @{ Accept = 'application/xml' }
            $resp = New-CIPPAzStorageRequest -Service 'blob' -Resource $Name -QueryParams @{ restype = 'container' } -Method 'DELETE' -Headers $headers -ConnectionString $ConnectionString
            if ($null -eq $resp) { return [PSCustomObject]@{ Name = $Name; StatusCode = 202; Headers = @{}; Uri = $null } }
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
