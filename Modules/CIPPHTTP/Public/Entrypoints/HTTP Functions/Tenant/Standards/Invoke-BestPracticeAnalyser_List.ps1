Function Invoke-BestPracticeAnalyser_List {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.BestPracticeAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Tenants = Get-Tenants
    $Table = get-cipptable 'cachebpa'
    $Results = (Get-CIPPAzDataTableEntity @Table) | ForEach-Object {
        $_.UnusedLicenseList = @(ConvertFrom-Json -ErrorAction silentlycontinue -InputObject $_.UnusedLicenseList)
        $_
    }

    if (!$Results) {
        $Results = @{
            Tenant = 'The BPA has not yet run.'
        }
    }
    Write-Host ($Tenants | ConvertTo-Json)
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @(($Results | Where-Object -Property RowKey -In $Tenants.customerId))
        })

}
