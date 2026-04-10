function Push-CIPPTestCollection {
    <#
    .SYNOPSIS
        Activity trigger: run all tests for a named suite against a tenant

    .DESCRIPTION
        Grouped test execution activity — the test-suite equivalent of the grouped
        CollectionType mode in Push-ExecCIPPDBCache. Delegates to Invoke-CIPPTestCollection
        which discovers and runs all matching Invoke-CippTest* functions via Get-Command
        (path-independent, ModuleBuilder compatible).

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $SuiteName = $Item.SuiteName

    try {
        Write-Information "Running $SuiteName suite for tenant $TenantFilter"

        $Result = Invoke-CIPPTestCollection -SuiteName $SuiteName -TenantFilter $TenantFilter

        Write-Information "Completed $SuiteName suite for $TenantFilter - $($Result.Success)/$($Result.Total) tests ran in $($Result.TotalSeconds)s"
        return "Successfully executed $SuiteName suite for $TenantFilter ($($Result.Success)/$($Result.Total) ran, $($Result.Failed) errored)"

    } catch {
        $ErrorMsg = "Failed to execute $SuiteName suite for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
