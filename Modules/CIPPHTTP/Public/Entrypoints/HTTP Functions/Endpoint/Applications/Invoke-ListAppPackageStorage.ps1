function Invoke-ListAppPackageStorage {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.Read
    .SYNOPSIS
        Shows how much storage uploaded app packages use.
    .DESCRIPTION
        Returns one row: UsedBytes, the space packages use in CIPP's own storage; LimitBytes, the limit on new
        uploads there (0 when there is none, including while a storage account is connected); AccountName, the
        storage account connected in Settings (empty when none); and AccountBytes, the space packages use in it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Storage = Get-CIPPAppPackageStorage
        $Files = @(Get-CIPPAppPackageFile -ErrorAction Stop)
        $Usage = [PSCustomObject]@{
            UsedBytes    = [int64]($Files.Where({ -not $_.Custom }).Size | Measure-Object -Sum).Sum
            LimitBytes   = [int64]$Storage.LimitBytes
            AccountName  = [string]$Storage.AccountName
            AccountBytes = [int64]($Files.Where({ $_.Custom }).Size | Measure-Object -Sum).Sum
        }
    } catch {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Failed to read app package storage: $($_.Exception.Message)" } })
    }

    return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @($Usage) })
}
