function Push-ExecCIPPDBCache {
    <#
    .SYNOPSIS
        Generic wrapper to execute CIPP DB cache functions

    .DESCRIPTION
        Supports two modes:
        - Grouped collection: When CollectionType is specified, delegates to Invoke-CIPPDBCacheCollection
          which runs all cache functions for that license group sequentially in one activity.
        - Single type (legacy): When Name is specified, executes a single Set-CIPPDBCache* function.
          Used by the HTTP endpoint for on-demand single-type cache refreshes.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $QueueId = $Item.QueueId

    try {
        # Grouped collection mode — runs all cache types for a license category in one activity
        if ($Item.CollectionType) {
            Write-Information "Collecting $($Item.CollectionType) group for tenant $TenantFilter"

            $Params = @{
                CollectionType = $Item.CollectionType
                TenantFilter   = $TenantFilter
            }
            if ($QueueId) { $Params.QueueId = $QueueId }

            $Result = Invoke-CIPPDBCacheCollection @Params

            Write-Information "Completed $($Item.CollectionType) group for $TenantFilter - $($Result.Success)/$($Result.Total) succeeded"
            return "Successfully executed $($Item.CollectionType) collection for $TenantFilter ($($Result.Success)/$($Result.Total))"
        }

        # Single-type mode (legacy) — used by HTTP endpoint for on-demand cache refresh
        $Name = $Item.Name
        $Types = @($Item.Types | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'None' })

        Write-Information "Collecting $Name for tenant $TenantFilter"

        # Build the full function name
        $FullFunctionName = "Set-CIPPDBCache$Name"

        # Check if function exists
        $Function = Get-Command -Name $FullFunctionName -ErrorAction SilentlyContinue
        if (-not $Function) {
            throw "Function $FullFunctionName does not exist"
        }

        # Build parameters for the cache function
        $CacheFunctionParams = @{
            TenantFilter = $TenantFilter
        }

        # Add QueueId if provided
        if ($QueueId) {
            $CacheFunctionParams.QueueId = $QueueId
        }

        # Add Types if provided (for Mailboxes function)
        $FunctionSupportsTypes = $Function.Parameters.ContainsKey('Types')
        if ($Types.Count -gt 0 -and $FunctionSupportsTypes) {
            $CacheFunctionParams.Types = $Types
        }

        Write-Information "Executing $FullFunctionName with parameters: $(($CacheFunctionParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))"

        # Execute the cache function
        & $FullFunctionName @CacheFunctionParams

        Write-Information "Completed $Name for tenant $TenantFilter"
        return "Successfully executed $Name for tenant $TenantFilter"

    } catch {
        $ErrorMsg = "Failed to execute $(if ($Item.CollectionType) { "$($Item.CollectionType) collection" } else { $Item.Name }) for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
