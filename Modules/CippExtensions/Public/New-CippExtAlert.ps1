function New-CippExtAlert {
    [CmdletBinding()]
    param (
        [switch]$TestRun = $false,
        [pscustomobject]$Alert
    )
    #Get the current CIPP Alerts table and see what system is configured to receive alerts
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-AzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
    $MappingTable = Get-CIPPTable -TableName CippMapping
    $MappingFile = (Get-AzDataTableEntity @MappingTable)
    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            "HaloPSA" {
                If ($Configuration.HaloPSA.enabled) {
                    $TenantId = (Get-Tenants | Where-Object defaultDomainName -EQ $Alert.TenantId).customerId
                    $MappedId = ($MappingFile | Where-Object RowKey -EQ $TenantId).HaloPSA
                    if (!$mappedId) { $MappedId = 1 }
                    New-HaloPSATicket -Title $Alert.AlertTitle -Description $Alert.AlertText -Client $mappedId 
                }
            }
            "Gradient" {
                If ($Configuration.Gradient.enabled) {
                    New-GradientAlert -Title $Alert.AlertTitle -Description $Alert.AlertText -Client $Alert.TenantId
                }
            }
        }
    }

}