function Push-ExecCIPPDBCache {
    <#
    .SYNOPSIS
        Generic wrapper to execute CIPP DB cache functions

    .DESCRIPTION
        Executes the specified Set-CIPPDBCache* function with the provided parameters

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Name = $Item.Name
    $TenantFilter = $Item.TenantFilter

    try {
        Write-Information "Collecting $Name for tenant $TenantFilter"

        # Build the full function name
        $FullFunctionName = "Set-CIPPDBCache$Name"

        # Check if function exists
        $Function = Get-Command -Name $FullFunctionName -ErrorAction SilentlyContinue
        if (-not $Function) {
            throw "Function $FullFunctionName does not exist"
        }

        # Execute the cache function
        & $FullFunctionName -TenantFilter $TenantFilter

        Write-Information "Completed $Name for tenant $TenantFilter"
        return "Successfully executed $Name for tenant $TenantFilter"

    } catch {
        $ErrorMsg = "Failed to execute $Name for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
