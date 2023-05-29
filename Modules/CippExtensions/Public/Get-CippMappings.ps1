function Get-CippMappings {
    [CmdletBinding()]
    param (
        [switch]$TestRun = $false,
        [pscustomobject]$Alert
    )
    Write-Host "Alert Run"
    #Get the current CIPP Alerts table and see what system is configured to receive alerts
    $Table = Get-CIPPTable -TableName ExtensionsMappingTable
    $Configuration = (Get-AzDataTableEntity @Table)
    Write-Host "Gotten config, going to run the foreach."
    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        Write-Host "In the foreach, running the loop for $ConfigItem"

        switch ($ConfigItem) {
            "HaloPSA" {
                If ($Configuration.HaloPSA.enabled) {
                    $MappedId = 
                    New-HaloPSATicket -Title "CIPP Alert" -Description "CIPP Alert" -client $mappedId -Priority "Low" -Type "Incident" -Status "New" -Source "CIPP" -Assignee "CIPP"
                }
            }
            "GradientTicketing" {
                If ($Configuration.GradientTicketing.enabled) {
                    Write-Host "Send Message to Gradient"
                }
            }
        }
    }

}