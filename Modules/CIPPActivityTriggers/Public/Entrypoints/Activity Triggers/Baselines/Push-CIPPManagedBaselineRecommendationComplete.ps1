function Push-CIPPManagedBaselineRecommendationComplete {
    <#
    .SYNOPSIS
        PostExecution for a recommendations scan: runs once after every standard has been compared.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    Complete-CIPPManagedBaselineRecommendationScan -Partition "$($Item.Parameters.Partition)" -ScanId "$($Item.Parameters.ScanId)"
}
